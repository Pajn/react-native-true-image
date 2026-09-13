package com.trueimage

import com.bumptech.glide.load.model.GlideUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The prefetch/view cache-key contract. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
class TrueImagePrefetchParityTest : GlideTestCase() {
  private val url = "https://cdn.example.com/cover.jpg"

  private fun view(): Pair<TrueImageView, MutableList<String>> {
    val events = mutableListOf<String>()
    val view = TrueImageView(app)
    view.eventSink = { name, _ -> events += name }
    return view to events
  }

  @Test
  fun prefetchedUrlIsASynchronousMemoryHitInTheView() {
    assertTrue(prefetch(url))
    val (view, events) = view()
    view.source = url
    view.transitionMs = 300
    view.commit()
    // Delivered inside commit(): nothing left to idle, and no fade because
    // a cached image in an empty view is not late.
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), events)
    assertTrue(view.hasImage)
    assertFalse(view.isCrossfading)
    assertFalse(view.hasPendingLoad)
  }

  @Test
  fun imageIsFetchedExactlyOnceAcrossPrefetchAndView() {
    prefetch(url)
    val (view, _) = view()
    view.source = url
    view.commit()
    settle()
    assertEquals(1, network.fetches[url])
  }

  @Test
  fun viewSizeKeyedRequestMissesThePrefetch() {
    prefetch(url)
    val glide = TrueImageRequests.glide(app)
    val hit = loadSync(TrueImageRequests.drawable(glide, GlideUrl(url)).onlyRetrieveFromCache(true))
    val miss = loadSync(glide.asDrawable().load(GlideUrl(url)).override(50, 50).onlyRetrieveFromCache(true))
    assertNotNull(hit)
    assertNull(miss)
  }

  @Test
  fun failedPrefetchDoesNotBlacklistTheUrl() {
    network.failOnce += url
    assertFalse(prefetch(url))
    val (view, events) = view()
    view.source = url
    view.commit()
    settle()
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), events)
    assertEquals(2, network.fetches[url])
  }

  @Test
  fun emptyListResolvesTrue() {
    assertTrue(prefetch())
  }

  @Test
  fun partialFailureResolvesFalseAndAllSuccessTrue() {
    val ok = "https://cdn.example.com/ok.jpg"
    val bad = "https://cdn.example.com/bad.jpg"
    network.failAlways += bad
    assertFalse(prefetch(ok, bad))
    assertTrue(prefetch(ok, "https://cdn.example.com/ok2.jpg"))
  }

  @Test
  fun unknownResourceNameInListResolvesFalse() {
    assertFalse(prefetch(url, "no_such_drawable"))
  }

  @Test
  fun prefetchedBitmapSurvivesIntoMemoryCacheAfterClear() {
    prefetch(url)
    val glide = TrueImageRequests.glide(app)
    assertNotNull(loadSync(TrueImageRequests.drawable(glide, GlideUrl(url)).onlyRetrieveFromCache(true)))
    assertEquals(1, network.fetches[url])
  }
}
