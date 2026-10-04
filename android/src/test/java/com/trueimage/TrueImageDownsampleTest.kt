package com.trueimage

import android.graphics.drawable.BitmapDrawable
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
class TrueImageDownsampleTest : GlideTestCase() {
  override val useDiskCache = true
  @Test
  fun thresholdIsStrictAndModesKeepEnoughDetail() {
    val cover = TrueImageDownsample(FitMode.COVER, 2f)
    assertEquals(1f, cover.getScaleFactor(200, 200, 100, 100), 0f)
    assertEquals(100f / 201, cover.getScaleFactor(201, 201, 100, 100), 0f)
    assertEquals(0.2f, cover.getScaleFactor(1000, 500, 100, 100), 0f)
    assertEquals(0.1f, TrueImageDownsample(FitMode.CONTAIN, 2f).getScaleFactor(1000, 500, 100, 100), 0f)
    assertEquals(0.2f, TrueImageDownsample(FitMode.STRETCH, 2f).getScaleFactor(1000, 500, 100, 100), 0f)
    assertEquals(1f, cover.getScaleFactor(1000, 100, 100, 100), 0f)
    assertEquals(1f, cover.getScaleFactor(50, 50, 100, 100), 0f)
    assertEquals(1f, TrueImageDownsample(FitMode.CENTER, 2f).getScaleFactor(1000, 1000, 100, 100), 0f)
    assertEquals(1f, TrueImageDownsample(FitMode.COVER, 0f).getScaleFactor(1000, 1000, 100, 100), 0f)
  }

  @Test
  fun sizedPrefetchReducesBitmapAndMatchesViewSynchronously() {
    val url = "https://cdn.example.com/sized.png"
    val size = TrueImageRequests.Size(2, 2)
    assertTrue(prefetch(TrueImagePrefetcher.Request(url, size = size)))
    val view = TrueImageView(app)
    view.layout(0, 0, 2, 2)
    val events = mutableListOf<String>()
    view.eventSink = { name, _ -> events += name }
    view.source = url
    view.transitionMs = 300
    view.commit()
    assertEquals(listOf("topLoad", "topDisplay", "topDisplayEnd"), events)
    val bitmap = (view.currentDrawable as BitmapDrawable).bitmap
    assertEquals(2, bitmap.width)
    assertEquals(2, bitmap.height)
    assertEquals(0.25f, TrueImageDownsample.sourceScale(bitmap), 0f)
    assertFalse(view.isCrossfading)
    assertEquals(1, network.fetches[url])
    view.layout(0, 0, 8, 8)
    settle { (view.currentDrawable as? BitmapDrawable)?.bitmap?.width == 8 }
    assertEquals(8, (view.currentDrawable as BitmapDrawable).bitmap.width)
    assertEquals(1, network.fetches[url])
  }

  @Test
  fun roughPrefetchDimensionsReuseAdequateVariantsButRespectThreshold() {
    val url = "https://cdn.example.com/rough.png"
    assertTrue(prefetch(TrueImagePrefetcher.Request(url, size = TrueImageRequests.Size(5, 5))))
    val view = TrueImageView(app)
    view.layout(0, 0, 4, 4)
    view.source = url
    view.commit()
    // 8px source retained by the 5px estimate also fits a 4px view at exactly 2x.
    assertTrue(view.hasImage)
    assertFalse(view.hasPendingLoad)
    assertEquals(8, (view.currentDrawable as BitmapDrawable).bitmap.width)
    view.layout(0, 0, 3, 3)
    settle { (view.currentDrawable as? BitmapDrawable)?.bitmap?.width == 4 }
    assertEquals(4, (view.currentDrawable as BitmapDrawable).bitmap.width)
    assertEquals(1, network.fetches[url])

    val smaller = TrueImageView(app)
    smaller.layout(0, 0, 2, 2)
    smaller.source = url
    smaller.commit()
    // Glide rounds this decode to 4px, adequate and within 2x for the smaller view.
    assertTrue(smaller.hasImage)
    assertEquals(4, (smaller.currentDrawable as BitmapDrawable).bitmap.width)
    smaller.layout(0, 0, 6, 6)
    // The full-resolution 8px variant is available for the larger view.
    assertEquals(8, (smaller.currentDrawable as BitmapDrawable).bitmap.width)
  }

  @Test
  fun evictedCompatibleVariantFallsBackToFreshDecode() {
    val url = "https://cdn.example.com/evicted.png"
    assertTrue(prefetch(TrueImagePrefetcher.Request(url, size = TrueImageRequests.Size(2, 2))))
    com.bumptech.glide.Glide.get(app).clearMemory()
    val view = TrueImageView(app)
    view.layout(0, 0, 1, 1)
    view.source = url
    view.commit()
    settle { view.hasImage }
    assertTrue(view.hasImage)
    assertEquals(1, (view.currentDrawable as BitmapDrawable).bitmap.width)
    assertEquals(1, network.fetches[url])
  }

  @Test
  fun zeroSizeWaitsForLayoutAndThresholdOptOutKeepsOriginal() {
    val view = TrueImageView(app)
    val url = "https://cdn.example.com/layout.png"
    view.source = url
    view.commit()
    settle()
    assertNull(network.fetches[url])
    view.layout(0, 0, 2, 2)
    settle { view.hasImage }
    assertEquals(2, (view.currentDrawable as BitmapDrawable).bitmap.width)
    view.downsampleThreshold = 0f
    view.commit()
    settle { (view.currentDrawable as? BitmapDrawable)?.bitmap?.width == 8 }
    assertEquals(8, (view.currentDrawable as BitmapDrawable).bitmap.width)
  }
}
