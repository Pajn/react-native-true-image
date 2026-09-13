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
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The module parses what JS sends and resolves through the prefetcher. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
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
}
