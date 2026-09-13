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
    val hit = loadSync(TrueImageRequests.drawable(glide, TrueImageRequests.model(app, url)!!).onlyRetrieveFromCache(true))
    val miss = loadSync(glide.asDrawable().load(TrueImageRequests.model(app, url)).override(50, 50).onlyRetrieveFromCache(true))
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
  fun headersAreSentButKeptOutOfTheCacheKey() {
    val headers = mapOf("Authorization" to "Bearer t", "X-Proxy" to "shelf")
    assertTrue(prefetch(TrueImagePrefetcher.Request(url, headers)))
    assertEquals(headers, network.headersSeen[url])

    // A view that names the same URL without headers still gets the memory hit.
    val (view, events) = view()
    view.source = url
    view.transitionMs = 300
    view.commit()
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), events)
    assertEquals(1, network.fetches[url])
  }

  @Test
  fun viewSendsItsHeaders() {
    val (view, events) = view()
    view.source = url
    view.headers = mapOf("Authorization" to "Bearer v")
    view.commit()
    settle { events.size >= 3 }
    assertEquals(mapOf("Authorization" to "Bearer v"), network.headersSeen[url])
  }

  @Test
  fun urlIdentityIgnoresHeaders() {
    val plain = TrueImageRequests.model(app, url) as GlideUrl
    val withHeaders = TrueImageRequests.model(app, url, mapOf("A" to "b")) as GlideUrl
    assertEquals(plain, withHeaders)
    assertEquals(plain.hashCode(), withHeaders.hashCode())
    assertEquals(mapOf("A" to "b"), withHeaders.headers)
  }

  @Test
  fun prefetchCompletesOffTheMainThread() {
    var thread: Thread? = null
    val result = java.util.concurrent.atomic.AtomicReference<Boolean?>(null)
    TrueImagePrefetcher.prefetch(app, listOf(TrueImagePrefetcher.Request(url))) {
      thread = Thread.currentThread()
      result.set(it)
    }
    settle { result.get() != null }
    assertTrue(result.get() == true)
    assertTrue(thread !== android.os.Looper.getMainLooper().thread)
  }

  @Test
  fun prefetchedBitmapSurvivesIntoMemoryCacheAfterClear() {
    prefetch(url)
    val glide = TrueImageRequests.glide(app)
    assertNotNull(loadSync(TrueImageRequests.drawable(glide, TrueImageRequests.model(app, url)!!).onlyRetrieveFromCache(true)))
    assertEquals(1, network.fetches[url])
  }
}
