package com.trueimage

import com.facebook.react.bridge.JavaOnlyArray
import com.facebook.react.bridge.JavaOnlyMap
import com.facebook.react.bridge.Callback
import com.facebook.react.bridge.CatalystInstance
import com.facebook.react.bridge.JavaScriptContextHolder
import com.facebook.react.bridge.JavaScriptModule
import com.facebook.react.bridge.UIManager
import com.facebook.react.turbomodule.core.interfaces.CallInvokerHolder
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.PromiseImpl
import com.facebook.react.bridge.ReactApplicationContext
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The module parses what JS sends and resolves through the prefetcher. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
// Real decoding and drawing, so getPixels returns the image's colours.
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TrueImageModuleTest : GlideTestCase() {
  /** The module only needs a Context; the bridge surface is unused. */
  private class TestReactContext(app: android.app.Application) : ReactApplicationContext(app) {
    override fun <T : JavaScriptModule> getJSModule(jsInterface: Class<T>): T = error("no JS in tests")
    override fun <T : NativeModule> hasNativeModule(nativeModuleInterface: Class<T>): Boolean = false
    override fun getNativeModules(): MutableCollection<NativeModule> = mutableListOf()
    override fun <T : NativeModule> getNativeModule(nativeModuleInterface: Class<T>): T? = null
    override fun getNativeModule(moduleName: String): NativeModule? = null
    override fun getCatalystInstance(): CatalystInstance = error("no bridge in tests")
    override fun hasActiveCatalystInstance(): Boolean = false
    override fun hasActiveReactInstance(): Boolean = false
    override fun hasCatalystInstance(): Boolean = false
    override fun hasReactInstance(): Boolean = false
    override fun destroy() = Unit
    override fun handleException(e: Exception) = throw e
    override fun isBridgeless(): Boolean = true
    override fun getJavaScriptContextHolder(): JavaScriptContextHolder? = null
    override fun getJSCallInvokerHolder(): CallInvokerHolder? = null
    override fun getFabricUIManager(): UIManager? = null
    override fun getSourceURL(): String? = null
    override fun registerSegment(segmentId: Int, path: String, callback: Callback) = Unit
  }

  private fun prefetchViaModule(vararg entries: Any?): Boolean {
    val module = TrueImageModule(TestReactContext(app))
    val value = AtomicReference<Any?>(null)
    val promise = PromiseImpl(
      Callback { args -> value.set(args[0]) },
      Callback { error("prefetch must resolve, never reject") },
    )
    module.prefetch(JavaOnlyArray.of(*entries), promise)
    settle { value.get() != null }
    return value.get() as Boolean
  }

  @Test
  fun resolvesTrueWhenEveryRequestLoads() {
    assertTrue(prefetchViaModule(JavaOnlyMap.of("uri", "https://cdn.example.com/a.jpg")))
    assertEquals(1, network.fetches["https://cdn.example.com/a.jpg"])
  }

  @Test
  fun passesHeadersThrough() {
    val headers = JavaOnlyArray.of(JavaOnlyMap.of("name", "Authorization", "value", "Bearer t"))
    assertTrue(prefetchViaModule(JavaOnlyMap.of("uri", "https://cdn.example.com/a.jpg", "headers", headers)))
    assertEquals(mapOf("Authorization" to "Bearer t"), network.headersSeen["https://cdn.example.com/a.jpg"])
  }

  @Test
  fun malformedEntriesForceFalseButValidOnesStillLoad() {
    assertFalse(prefetchViaModule("junk", JavaOnlyMap(), JavaOnlyMap.of("uri", "https://cdn.example.com/a.jpg")))
    assertEquals(1, network.fetches["https://cdn.example.com/a.jpg"])
  }

  @Test
  fun emptyListResolvesTrue() {
    assertTrue(prefetchViaModule())
  }

  /** The base64 string getPixels resolves, or null. */
  private fun pixelsViaModule(uri: String, size: Double, headers: JavaOnlyArray? = null, cacheKey: String? = null): String? {
    val module = TrueImageModule(TestReactContext(app))
    val value = AtomicReference<Array<out Any?>?>(null)
    val promise = PromiseImpl(
      Callback { args -> value.set(args) },
      Callback { error("getPixels must resolve, never reject") },
    )
    module.getPixels(uri, size, headers, cacheKey, promise)
    settle { value.get() != null }
    return value.get()!![0] as String?
  }

  @Test
  fun getPixelsResolvesTheImageAsRgbaAtTheRequestedSize() {
    val encoded = pixelsViaModule("https://cdn.example.com/a.jpg", 16.0)!!
    val bytes = android.util.Base64.decode(encoded, android.util.Base64.NO_WRAP)
    assertEquals(16 * 16 * 4, bytes.size)
    // The fake network serves an opaque (200, 50, 50) square.
    for (i in bytes.indices step 4) {
      assertEquals(listOf(200, 50, 50, 255), (0 until 4).map { bytes[i + it].toInt() and 0xff })
    }
    assertEquals(1, network.fetches["https://cdn.example.com/a.jpg"])
  }

  @Test
  fun getPixelsPassesHeadersThrough() {
    val headers = JavaOnlyArray.of(JavaOnlyMap.of("name", "Authorization", "value", "Bearer t"))
    pixelsViaModule("https://cdn.example.com/a.jpg", 16.0, headers)
    assertEquals(mapOf("Authorization" to "Bearer t"), network.headersSeen["https://cdn.example.com/a.jpg"])
  }

  @Test
  fun getPixelsFetchesWhenTheVariantIsGone() {
    val requested = "https://cdn.example.com/album?size=80"
    TrueImageVariants.record(app, "album", "https://cdn.example.com/album?size=512", 512, 512)
    assertNotNull(pixelsViaModule(requested, 16.0, cacheKey = "album"))
    assertEquals(1, network.fetches[requested])
    assertNull(network.fetches["https://cdn.example.com/album?size=512"])
    assertEquals(listOf(requested), TrueImageVariants.variants(app, "album").map { it.url })
  }

  @Test
  fun prefetchPassesTheCacheKeyThrough() {
    assertTrue(prefetchViaModule(JavaOnlyMap.of("uri", "https://cdn.example.com/a.jpg", "cacheKey", "a")))
    assertEquals(listOf("https://cdn.example.com/a.jpg"), TrueImageVariants.variants(app, "a").map { it.url })
  }

  @Test
  fun getPixelsResolvesNullWhenTheLoadFails() {
    network.failAlways += "https://cdn.example.com/missing.jpg"
    assertNull(pixelsViaModule("https://cdn.example.com/missing.jpg", 16.0))
  }

  @Test
  fun getPixelsResolvesNullForAnUnusableSize() {
    for (size in listOf(0.0, -1.0, Double.NaN, 257.0)) {
      assertNull(pixelsViaModule("https://cdn.example.com/a.jpg", size))
    }
    assertEquals(null, network.fetches["https://cdn.example.com/a.jpg"])
  }
}
