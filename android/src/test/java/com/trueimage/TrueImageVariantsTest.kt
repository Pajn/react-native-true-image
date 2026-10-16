package com.trueimage

import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import com.bumptech.glide.Glide
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock

/** cacheKey: one picture at several URLs, and the index that remembers them. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
class TrueImageVariantsTest : GlideTestCase() {
  override val useDiskCache = true

  private val key = "album-1"
  private val small = "https://img.example.com/album-1?size=8"
  private val requested = "https://img.example.com/album-1?size=32"
  private val big = "https://img.example.com/album-1?size=64"
  private val thumb = "https://img.example.com/thumb.jpg"

  /** The view's own decode settings, so a sized prefetch is its memory hit. */
  private val viewSize = TrueImageRequests.Size(32, 32)

  private class Harness(val view: TrueImageView) {
    val events = mutableListOf<Pair<String, Map<String, Any>>>()
    val names get() = events.map { it.first }

    init {
      view.eventSink = { name, payload -> events += name to payload }
    }

    fun set(source: String?, cacheKey: String? = null, transition: Int = 0, recyclingKey: String? = null) {
      view.source = source
      view.cacheKey = cacheKey
      view.transitionMs = transition
      if (recyclingKey != null) view.recyclingKey = recyclingKey
      view.commit()
    }

    val width: Int? get() = (view.currentDrawable as? BitmapDrawable)?.bitmap?.width
  }

  private fun harness() = Harness(TrueImageView(app).apply { layout(0, 0, 32, 32) })

  @Before
  fun sizes() {
    network.sizes[small] = 8 to 8
    network.sizes[requested] = 32 to 32
    network.sizes[big] = 64 to 64
    network.sizes[thumb] = 16 to 16
  }

  private fun prefetchVariant(url: String, cacheKey: String = key, size: TrueImageRequests.Size = viewSize) =
    assertTrue(prefetch(TrueImagePrefetcher.Request(url, size = size, cacheKey = cacheKey)))

  /** Lets a held fetch through once Glide's worker has actually started it. */
  private fun release(url: String) {
    settle { network.isHeld(url) }
    network.release(url)
  }

  private fun urls(cacheKey: String = key) = TrueImageVariants.variants(app, cacheKey).map { it.url }

  // MARK: Index

  @Test
  fun prefetchRecordsTheSourceSizeOfItsVariant() {
    // Decoded near 8 px, recorded at the 64 px any decode of it can reach.
    prefetchVariant(big, size = TrueImageRequests.Size(8, 8, FitMode.COVER, 1f))
    assertEquals(listOf(TrueImageVariants.Variant(big, 64, 64)), TrueImageVariants.variants(app, key))
  }

  @Test
  fun indexSurvivesAProcessRestart() {
    TrueImageVariants.record(app, key, small, 80, 80)
    TrueImageVariants.record(app, key, big, 512, 512)
    TrueImageVariants.record(app, "album-2", thumb, 256, 256)
    TrueImageVariants.flush()
    assertTrue(TrueImageVariants.file(app).exists())
    TrueImageVariants.reload(app)
    assertEquals(
      listOf(TrueImageVariants.Variant(small, 80, 80), TrueImageVariants.Variant(big, 512, 512)),
      TrueImageVariants.variants(app, key),
    )
    assertEquals(listOf(thumb), urls("album-2"))
  }

  @Test
  fun recordingAgainUpdatesTheVariantInPlace() {
    TrueImageVariants.record(app, key, small, 80, 80)
    TrueImageVariants.record(app, key, big, 512, 512)
    TrueImageVariants.record(app, key, small, 100, 100)
    assertEquals(
      listOf(TrueImageVariants.Variant(big, 512, 512), TrueImageVariants.Variant(small, 100, 100)),
      TrueImageVariants.variants(app, key),
    )
  }

  @Test
  fun keysAreBoundedLeastRecentlyUsedFirstAcrossRestarts() {
    for (i in 0 until TrueImageVariants.MAX_KEYS) TrueImageVariants.record(app, "k$i", "$small&k=$i", 8, 8)
    // Reading k0 makes k1 the least recently used.
    TrueImageVariants.variants(app, "k0")
    TrueImageVariants.record(app, "new", small, 8, 8)
    assertEquals(1, urls("k0").size)
    assertTrue(urls("k1").isEmpty())
    assertEquals(1, urls("new").size)
    TrueImageVariants.flush()
    TrueImageVariants.reload(app)
    assertEquals(1, urls("k0").size)
    assertTrue(urls("k1").isEmpty())
    assertEquals(1, urls("k2").size)
  }

  @Test
  fun variantsPerKeyAreBounded() {
    for (i in 0 until TrueImageVariants.MAX_VARIANTS + 2) TrueImageVariants.record(app, key, "$small&v=$i", 8 + i, 8 + i)
    assertEquals(
      (2 until TrueImageVariants.MAX_VARIANTS + 2).map { "$small&v=$it" },
      urls(),
    )
  }

  @Test
  fun corruptIndexFileStartsEmptyAndIsReplaced() {
    TrueImageVariants.file(app).writeText("{\"version\":1,\"keys\":[{\"key\":")
    TrueImageVariants.reload(app)
    assertTrue(urls().isEmpty())
    TrueImageVariants.record(app, key, big, 512, 512)
    TrueImageVariants.flush()
    TrueImageVariants.reload(app)
    assertEquals(listOf(big), urls())
  }

  @Test
  fun malformedEntriesAreSkippedAndOtherVersionsIgnored() {
    val parsed = TrueImageVariants.parse(
      """
      {"version":1,"keys":[
        {"key":"a","variants":[{"url":"https://x/a","width":10,"height":10},{"url":"","width":5,"height":5}]},
        {"key":"b","variants":[{"url":"https://x/b","width":0,"height":10}]},
        {"variants":[{"url":"https://x/c","width":10,"height":10}]},
        "junk"
      ]}
      """.trimIndent(),
    )
    assertEquals(listOf("a" to listOf(TrueImageVariants.Variant("https://x/a", 10, 10))), parsed)
    assertTrue(TrueImageVariants.parse("{\"version\":2,\"keys\":[]}").isEmpty())
  }

  // MARK: View

  @Test
  fun sufficientVariantInMemoryIsShownSynchronouslyWithoutFetching() {
    prefetchVariant(big)
    val h = harness()
    h.set(requested, key, transition = 300)
    // Inside commit and without a fade, as an exact memory hit would be.
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertFalse(h.view.isCrossfading)
    assertFalse(h.view.hasPendingLoad)
    assertEquals("onLoad names the source the view asked for", requested, h.events[0].second["source"])
    assertEquals("and the size of the image actually shown", 64.0, h.events[0].second["width"])
    assertNull("the requested URL is never fetched", network.fetches[requested])
    assertEquals(1, network.fetches[big])
  }

  @Test
  fun sufficientVariantOnDiskIsDecodedWithoutTheNetwork() {
    prefetchVariant(big)
    Glide.get(app).clearMemory()
    val h = harness()
    h.set(requested, key)
    assertFalse("a disk read is not synchronous", h.view.hasImage)
    settle { h.events.size >= 3 }
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertEquals(64, h.width)
    assertNull(network.fetches[requested])
    assertEquals(1, network.fetches[big])
  }

  @Test
  fun committingAgainKeepsTheReusedVariant() {
    prefetchVariant(big)
    val h = harness()
    h.set(requested, key)
    h.events.clear()
    h.set(requested, key)
    settle()
    assertTrue(h.events.isEmpty())
    assertNull(network.fetches[requested])
  }

  @Test
  fun smallerVariantStandsInUntilTheImageArrivesThenCrossfades() {
    prefetchVariant(small)
    network.hang += requested
    val h = harness()
    h.view.placeholderTransitionMs = 200
    h.set(requested, key, transition = 300)
    assertTrue("a memory-cached variant shows inside commit", h.view.isShowingPlaceholder)
    assertEquals(8, h.width)
    assertTrue("a stand-in reports nothing", h.events.isEmpty())
    assertEquals(1, network.fetches[requested])
    release(requested)
    settle { h.names.contains("topLoad") }
    assertEquals(listOf("topLoad", "topDisplay"), h.names)
    assertEquals(32.0, h.events[0].second["width"])
    assertTrue("leaving the stand-in crossfades over placeholderTransition", h.view.isCrossfading)
    assertFalse(h.view.isShowingPlaceholder)
    ShadowSystemClock.advanceBy(Duration.ofMillis(250))
    h.view.draw(Canvas())
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertEquals(listOf(small, requested), urls())
  }

  @Test
  fun smallerVariantOnDiskStandsInAsynchronously() {
    prefetchVariant(small)
    Glide.get(app).clearMemory()
    network.hang += requested
    val h = harness()
    h.set(requested, key)
    settle { h.view.isShowingPlaceholder }
    assertEquals(8, h.width)
    assertTrue(h.events.isEmpty())
  }

  @Test
  fun evictedVariantIsForgottenAndTheSourceIsFetched() {
    // Recorded by an earlier process; the caches no longer have it.
    TrueImageVariants.record(app, key, big, 64, 64)
    val h = harness()
    h.set(requested, key)
    settle { h.events.size >= 3 }
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertEquals(32, h.width)
    assertEquals(1, network.fetches[requested])
    assertNull("a cache-only lookup never fetches", network.fetches[big])
    assertEquals(listOf(requested), urls())
  }

  @Test
  fun exactUrlInMemoryWinsOverAVariant() {
    prefetchVariant(big)
    prefetchVariant(requested)
    val h = harness()
    h.set(requested, key)
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertEquals(32, h.width)
    assertEquals(1, network.fetches[requested])
  }

  @Test
  fun withoutACacheKeyNothingChanges() {
    prefetchVariant(big)
    prefetchVariant(small)
    network.hang += requested
    val h = harness()
    h.set(requested)
    assertFalse(h.view.hasImage)
    assertFalse("no stand-in without a cache key", h.view.isShowingPlaceholder)
    release(requested)
    settle { h.events.size >= 3 }
    assertEquals(32, h.width)
    assertEquals(1, network.fetches[requested])
  }

  @Test
  fun variantIsTooSmallForALargerView() {
    prefetchVariant(big)
    val h = Harness(TrueImageView(app).apply { layout(0, 0, 100, 100) })
    network.sizes[requested] = 128 to 128
    h.set(requested, key)
    settle { h.events.size >= 3 }
    assertEquals(128, h.width)
    assertEquals(1, network.fetches[requested])
  }

  @Test
  fun sameKeyVariantBeatsACacheOnlyPlaceholder() {
    prefetchVariant(small)
    assertTrue(prefetch(TrueImagePrefetcher.Request(thumb, size = viewSize)))
    network.hang += requested
    val h = harness()
    h.view.placeholder = thumb
    h.set(requested, key)
    assertTrue(h.view.isShowingPlaceholder)
    assertEquals("the same picture, not the explicit placeholder", 8, h.width)
  }

  @Test
  fun networkPlaceholderIsTheAppsChoiceAndWins() {
    prefetchVariant(small)
    assertTrue(prefetch(TrueImagePrefetcher.Request(thumb, size = viewSize)))
    network.hang += requested
    val h = harness()
    h.view.placeholder = thumb
    h.view.placeholderFromNetwork = true
    h.set(requested, key)
    assertTrue(h.view.isShowingPlaceholder)
    assertEquals(16, h.width)
  }

  @Test
  fun cacheOnlyPlaceholderIsTheFallbackWhenTheVariantIsGone() {
    TrueImageVariants.record(app, key, small, 8, 8)
    assertTrue(prefetch(TrueImagePrefetcher.Request(thumb, size = viewSize)))
    network.hang += requested
    val h = harness()
    h.view.placeholder = thumb
    h.set(requested, key)
    assertTrue("the explicit placeholder's memory hit is still synchronous", h.view.isShowingPlaceholder)
    assertEquals(16, h.width)
  }

  @Test
  fun recycledRowReusesAVariantWithoutCrossfadingThePreviousItem() {
    val otherRequested = "https://img.example.com/album-2?size=32"
    val otherBig = "https://img.example.com/album-2?size=64"
    network.sizes[otherBig] = 64 to 64
    prefetchVariant(big)
    prefetchVariant(otherBig, cacheKey = "album-2")
    val h = harness()
    h.set(requested, key, transition = 300, recyclingKey = "1")
    h.events.clear()
    h.set(otherRequested, "album-2", transition = 300, recyclingKey = "2")
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertFalse(h.view.isCrossfading)
    assertNull(network.fetches[otherRequested])
  }

  @Test
  fun getPixelsSamplesACachedVariantInsteadOfFetching() {
    prefetchVariant(big)
    val result = java.util.concurrent.atomic.AtomicReference<Result<String?>?>(null)
    TrueImagePixels.load(app, requested, null, 16, key) { result.set(Result.success(it)) }
    settle { result.get() != null }
    val encoded = result.get()!!.getOrNull()!!
    assertEquals(16 * 16 * 4, android.util.Base64.decode(encoded, android.util.Base64.NO_WRAP).size)
    assertNull(network.fetches[requested])
    assertEquals(1, network.fetches[big])
  }

  @Test
  fun reusedVariantReplacingADisplayedImageCrossfadesAndReportsOnce() {
    val other = "https://img.example.com/other.jpg"
    prefetchVariant(big)
    prefetch(TrueImagePrefetcher.Request(other, size = viewSize))
    val h = harness()
    h.set(other, transition = 300)
    h.events.clear()
    h.set(requested, key, transition = 300)
    assertEquals("a replacement always crossfades", listOf("topLoad", "topDisplay"), h.names)
    assertTrue(h.view.isCrossfading)
    ShadowSystemClock.advanceBy(Duration.ofMillis(400))
    h.view.draw(Canvas())
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
  }
}
