package com.trueimage

import android.app.Activity
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock

/** Native view behaviour: fades, events, clearing, lifecycle. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
class TrueImageViewTest : GlideTestCase() {
  private val a = "https://cdn.example.com/a.jpg"
  private val b = "https://cdn.example.com/b.jpg"

  private class Harness(val view: TrueImageView) {
    val events = mutableListOf<Pair<String, Map<String, Any>>>()
    val names get() = events.map { it.first }

    init {
      view.eventSink = { name, payload -> events += name to payload }
    }

    fun set(source: String?, transition: Int = 0, recyclingKey: String? = null) {
      view.source = source
      view.transitionMs = transition
      if (recyclingKey != null) view.recyclingKey = recyclingKey
      view.commit()
    }

    fun draw() = view.draw(Canvas())
  }

  private fun harness() = Harness(TrueImageView(app))

  private fun advance(ms: Long) = ShadowSystemClock.advanceBy(Duration.ofMillis(ms))

  @Test
  fun recycledViewWithCachedImageDrawsAtOnceWithoutFade() {
    prefetch(a, b)
    val h = harness()
    h.set(a, transition = 300, recyclingKey = "1")
    h.events.clear()
    h.set(b, transition = 300, recyclingKey = "2")
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertFalse(h.view.isCrossfading)
  }

  @Test
  fun noFadePathEmitsAllThreeEventsInOneFrame() {
    val h = harness()
    h.set(a, transition = 0)
    settle()
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertEquals(8.0, h.events[0].second["width"])
    assertEquals(a, h.events[0].second["source"])
  }

  @Test
  fun fadePathEmitsDisplayEndOnlyWhenTheFadeEnds() {
    val h = harness()
    h.set(a, transition = 300)
    settle()
    assertEquals(listOf("topLoad", "topDisplay"), h.names)
    assertTrue(h.view.isCrossfading)
    advance(100)
    h.draw()
    assertEquals(listOf("topLoad", "topDisplay"), h.names)
    advance(300)
    h.draw()
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertFalse(h.view.isCrossfading)
  }

  @Test
  fun interruptedFadeReportsDisplayEndOnlyForTheImageStillShown() {
    val h = harness()
    h.set(a, transition = 300)
    settle()
    advance(100)
    h.draw()
    h.set(b, transition = 300)
    settle()
    assertEquals(listOf("topLoad", "topDisplay", "topLoad", "topDisplay"), h.names)
    advance(500)
    h.draw()
    assertEquals(listOf("topLoad", "topDisplay", "topLoad", "topDisplay", "topDisplayEnd"), h.names)
  }

  @Test
  fun nullSourceClearsAndEmitsNothing() {
    prefetch(a)
    val h = harness()
    h.set(a)
    h.events.clear()
    h.set(null)
    assertFalse(h.view.hasImage)
    assertTrue(h.events.isEmpty())
  }

  @Test
  fun recyclingKeyChangeClearsSynchronouslyBeforeTheNewLoad() {
    prefetch(a)
    network.hang += b
    val h = harness()
    h.set(a, recyclingKey = "1")
    assertTrue(h.view.hasImage)
    h.set(b, recyclingKey = "2")
    assertFalse(h.view.hasImage)
    assertTrue(h.view.hasPendingLoad)
  }

  @Test
  fun staleTargetEmitsNeitherLoadNorError() {
    network.hang += a
    prefetch(b)
    val h = harness()
    h.set(a)
    h.set(b)
    h.events.clear()
    network.release(a)
    settle()
    assertTrue(h.events.isEmpty())
    assertTrue(h.view.hasImage)
  }

  @Test
  fun loadCancelledByNewerSourceDoesNotEmitError() {
    network.failAlways += a
    network.hang += a
    val h = harness()
    h.set(a)
    h.set(b)
    settle()
    assertFalse(h.names.contains("topError"))
  }

  @Test
  fun unknownDrawableNameEmitsErrorAndLeavesViewEmpty() {
    val h = harness()
    h.set("no_such_drawable")
    assertEquals(listOf("topError"), h.names)
    assertEquals("no_such_drawable", h.events[0].second["source"])
    assertFalse(h.view.hasImage)
  }

  @Test
  fun failedRemoteLoadEmitsError() {
    network.failAlways += a
    val h = harness()
    h.set(a)
    settle()
    assertEquals(listOf("topError"), h.names)
  }

  @Test
  fun vectorResourceDrawsInTheSameFrameAndNeverFades() {
    val h = harness()
    h.set("true_image_test_vector", transition = 300)
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertFalse(h.view.isCrossfading)
    assertTrue(h.view.hasImage)
  }

  @Test
  fun tintIsNotAppliedToRemoteBitmaps() {
    prefetch(a)
    val h = harness()
    h.view.tintColor = 0xFFFF0000.toInt()
    h.set(a)
    val drawable = h.view.currentDrawable as BitmapDrawable
    assertNull(drawable.paint.colorFilter)
  }

  @Test
  fun blurredImageIsBlurredOnceOffTheMainThreadAndNeverShownSharp() {
    prefetch(a)
    val h = harness()
    h.view.blurRadius = 10f
    h.view.layout(0, 0, 100, 100)
    h.set(a)
    assertFalse("the blur is still running; nothing shows yet", h.view.hasImage)
    assertTrue(h.view.hasPendingLoad)
    settle { h.view.hasImage }
    assertNotNull(h.view.currentBlurred)
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    // 8 px shrunk by 10 / 2 = 5 is 2 px.
    assertEquals(2, (h.view.currentBlurred as BitmapDrawable).bitmap.width)
    assertEquals(1, network.fetches[a])
  }

  @Test
  fun blurredImageSurvivesResizeAndFollowsBlurChanges() {
    prefetch(a)
    val h = harness()
    h.view.blurRadius = 10f
    h.view.layout(0, 0, 100, 100)
    h.set(a)
    settle { h.view.hasImage }
    val first = h.view.currentBlurred
    h.view.layout(0, 0, 200, 200)
    h.draw()
    assertSame("the blur is independent of view size", first, h.view.currentBlurred)
    h.view.blurRadius = 20f
    h.view.commit()
    assertSame("the old blur stays up until the new one is ready", first, h.view.currentBlurred)
    settle { h.view.currentBlurred !== first }
    val second = h.view.currentBlurred
    assertNotSame(first, second)
    h.view.blurPixelsPerRadius = 4f
    h.view.commit()
    settle { h.view.currentBlurred !== second }
    assertNotSame(second, h.view.currentBlurred)
    h.view.blurRadius = 0f
    h.view.commit()
    assertNull("clearing the blur switches to the sharp image at once", h.view.currentBlurred)
    assertTrue(h.view.hasImage)
    assertEquals(1, network.fetches[a])
  }

  @Test
  fun blurredImageIsSharedByRecycledViews() {
    prefetch(a)
    val first = harness()
    first.view.blurRadius = 10f
    first.set(a)
    settle { first.view.hasImage }
    val second = harness()
    second.view.blurRadius = 10f
    second.set(a)
    assertTrue("a cached blur is a synchronous hit", second.view.hasImage)
    assertNotNull(second.view.currentBlurred)
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), second.names)
  }

  @Test
  fun newerSourceCancelsAPendingBlur() {
    prefetch(a, b)
    val h = harness()
    h.view.blurRadius = 10f
    h.set(a)
    h.set(b)
    settle { h.view.hasImage }
    assertEquals(b, h.events.first { it.first == "topLoad" }.second["source"])
    assertEquals(1, h.events.count { it.first == "topLoad" })
  }

  @Test
  fun attachingReloadsAViewWhoseImageWasTaken() {
    prefetch(a)
    val h = harness()
    h.view.source = a
    assertFalse(h.view.hasImage)
    val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    activity.setContentView(h.view)
    assertTrue(h.view.hasImage)
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
  }

  @Test
  fun releaseClearsEverything() {
    prefetch(a)
    network.hang += b
    val h = harness()
    h.set(a, transition = 300)
    h.set("https://cdn.example.com/c.jpg", transition = 300)
    settle()
    assertTrue(h.view.isCrossfading)
    h.view.source = b
    h.view.commit()
    assertTrue(h.view.hasPendingLoad)
    h.view.release()
    assertFalse(h.view.hasImage)
    assertFalse(h.view.isCrossfading)
    assertFalse(h.view.hasPendingLoad)
  }

  @Test
  fun interruptedFadeInResumesFromItsCurrentAlpha() {
    val h = harness()
    h.set(a, transition = 400)
    settle()
    advance(200)
    h.draw()
    assertEquals(0.5f, h.view.fadeAlpha!!, 0.05f)
    h.set(b, transition = 400)
    settle()
    // The view as a whole carries on from where it was; the new image does not restart at zero.
    assertEquals(0.5f, h.view.fadeAlpha!!, 0.1f)
    advance(400)
    h.draw()
    assertEquals(1, h.names.count { it == "topDisplayEnd" })
  }

  @Test
  fun replacementInterruptedByAnotherReplacementReportsOnce() {
    prefetch(a, b, "https://cdn.example.com/c.jpg")
    val h = harness()
    h.set(a, transition = 300)
    h.set(b, transition = 300)
    advance(100)
    h.draw()
    h.set("https://cdn.example.com/c.jpg", transition = 300)
    h.events.clear()
    advance(500)
    h.draw()
    assertEquals(listOf("topDisplayEnd"), h.names)
    assertFalse(h.view.isCrossfading)
  }

  @Test
  fun bitmapResourceLoadsThroughGlideAndNeverFades() {
    val h = harness()
    h.set("true_image_test_bitmap", transition = 300)
    settle { h.events.size >= 3 }
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
    assertFalse(h.view.isCrossfading)
  }

  @Test
  fun committingTheSameSourceAgainDoesNotReload() {
    val h = harness()
    h.set(a)
    settle()
    h.set(a)
    h.view.commit()
    settle()
    assertEquals(1, network.fetches[a])
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
  }

  @Test
  fun reapplyingTheSameRecyclingKeyDoesNotClear() {
    prefetch(a)
    val h = harness()
    h.set(a, recyclingKey = "1")
    h.events.clear()
    h.set(a, recyclingKey = "1")
    assertTrue(h.view.hasImage)
    assertTrue(h.events.isEmpty())
  }

  @Test
  fun blurChangeDoesNotReload() {
    prefetch(a)
    val h = harness()
    h.set(a)
    h.view.blurRadius = 12f
    h.view.commit()
    settle()
    assertEquals(1, network.fetches[a])
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), h.names)
  }

  @Test
  fun twoViewsSharingACachedImageDoNotShareADrawable() {
    prefetch(a)
    val first = harness()
    val second = harness()
    first.set(a)
    second.set(a)
    assertNotSame(first.view.currentDrawable, second.view.currentDrawable)
  }
}
