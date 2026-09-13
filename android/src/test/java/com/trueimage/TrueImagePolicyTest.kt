package com.trueimage

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FitTest {
  private fun assertRect(expected: FitRect, actual: FitRect) {
    assertEquals(expected.left, actual.left, 0.001f)
    assertEquals(expected.top, actual.top, 0.001f)
    assertEquals(expected.width, actual.width, 0.001f)
    assertEquals(expected.height, actual.height, 0.001f)
  }

  @Test
  fun coverOverflowsAndCentres() {
    // 200x100 image in a 100x100 box: scale to 100 tall, 200 wide, centred.
    assertRect(FitRect(-50f, 0f, 200f, 100f), Fit.rect(100f, 100f, 200f, 100f, FitMode.COVER))
  }

  @Test
  fun containInsetsAndCentres() {
    assertRect(FitRect(0f, 25f, 100f, 50f), Fit.rect(100f, 100f, 200f, 100f, FitMode.CONTAIN))
  }

  @Test
  fun stretchFillsBounds() {
    assertRect(FitRect(0f, 0f, 100f, 40f), Fit.rect(100f, 40f, 200f, 100f, FitMode.STRETCH))
  }

  @Test
  fun centerDrawsAtIntrinsicSize() {
    assertRect(FitRect(-50f, 25f, 200f, 50f), Fit.rect(100f, 100f, 200f, 50f, FitMode.CENTER))
  }

  @Test
  fun degenerateIntrinsicFallsBackToBounds() {
    assertRect(FitRect(0f, 0f, 100f, 60f), Fit.rect(100f, 60f, 0f, 100f, FitMode.COVER))
    assertRect(FitRect(0f, 0f, 100f, 60f), Fit.rect(100f, 60f, -1f, -1f, FitMode.CONTAIN))
  }
}

class CrossfadeTest {
  @Test
  fun rampsFromZeroToOne() {
    val fade = Crossfade(durationMs = 400, startTimeMs = 1000)
    assertEquals(0f, fade.alpha(1000), 0.001f)
    assertEquals(0.5f, fade.alpha(1200), 0.001f)
    assertEquals(1f, fade.alpha(1400), 0.001f)
    assertEquals(1f, fade.alpha(9000), 0.001f)
    assertFalse(fade.isDone(1399))
    assertTrue(fade.isDone(1400))
  }

  @Test
  fun resumesFromInterruptedAlpha() {
    val fade = Crossfade(durationMs = 400, startTimeMs = 0, startAlpha = 0.6f)
    assertEquals(0.6f, fade.alpha(0), 0.001f)
    assertEquals(0.8f, fade.alpha(200), 0.001f)
    assertEquals(1f, fade.alpha(400), 0.001f)
  }

  @Test
  fun zeroDurationIsImmediatelyDone() {
    val fade = Crossfade(durationMs = 0, startTimeMs = 0)
    assertEquals(1f, fade.alpha(0), 0.001f)
    assertTrue(fade.isDone(0))
  }

  @Test
  fun clampsBeforeStart() {
    val fade = Crossfade(durationMs = 400, startTimeMs = 1000)
    assertEquals(0f, fade.alpha(500), 0.001f)
  }
}

class BlurTest {
  @Test
  fun downscaleFactorKeepsTheRequestedPixelsPerRadius() {
    assertEquals(50f, Blur.downscaleFactor(100f, Blur.DEFAULT_PIXELS_PER_RADIUS), 0f)
    assertEquals(25f, Blur.downscaleFactor(100f, 4f), 0f)
  }

  @Test
  fun downscaleFactorNeverUpscales() {
    assertEquals(1f, Blur.downscaleFactor(1f, 2f), 0f)
    assertEquals(1f, Blur.downscaleFactor(0f, 2f), 0f)
  }

  @Test
  fun zeroPixelsPerRadiusDisablesTheShrink() {
    assertEquals(1f, Blur.downscaleFactor(100f, 0f), 0f)
    assertEquals(1f, Blur.downscaleFactor(100f, -1f), 0f)
  }

  @Test
  fun downscaleSizeRoundsUpAndStaysAtLeastOnePixel() {
    assertEquals(80 to 60, Blur.downscaleSize(4000, 3000, 50f))
    assertEquals(3 to 1, Blur.downscaleSize(101, 10, 50f))
    assertEquals(10 to 10, Blur.downscaleSize(10, 10, 1f))
  }

  @Test
  fun boxSizeIsOddAndZeroForNoBlur() {
    assertEquals(0, Blur.boxSize(0f))
    for (sigma in listOf(0.5f, 1f, 2f, 7f, 100f)) assertEquals(1, Blur.boxSize(sigma) % 2)
    assertTrue(Blur.boxSize(100f) > Blur.boxSize(2f))
  }

  @Test
  fun blurLeavesAFlatImageAlone() {
    val pixels = IntArray(16) { 0xffc83232.toInt() }
    Blur.blur(pixels, 4, 4, 3f)
    assertTrue(pixels.all { it == 0xffc83232.toInt() })
  }

  @Test
  fun blurSpreadsASpikeSymmetrically() {
    // A white pixel on opaque black.
    val w = 9
    val pixels = IntArray(w * w) { 0xff000000.toInt() }
    pixels[4 * w + 4] = 0xffffffff.toInt()
    Blur.blur(pixels, w, w, 1f)
    val centre = pixels[4 * w + 4] and 0xff
    assertTrue(centre in 1..254)
    assertEquals(pixels[4 * w + 3], pixels[4 * w + 5])
    assertEquals(pixels[3 * w + 4], pixels[5 * w + 4])
    assertTrue((pixels[4 * w + 3] and 0xff) in 1 until centre)
    assertTrue("alpha stays opaque", pixels.all { (it ushr 24) == 0xff })
  }

  @Test
  fun blurDoesNotBleedColourOutOfTransparentPixels() {
    // A fully transparent green pixel next to opaque red must not tint the red green.
    val pixels = intArrayOf(0x00ff00ff.toInt(), 0xffff0000.toInt(), 0xffff0000.toInt(), 0xffff0000.toInt())
    Blur.blur(pixels, 4, 1, 1f)
    for (p in pixels) {
      if ((p ushr 24) == 0) continue
      assertEquals(0, (p ushr 8) and 0xff)
      assertEquals(0, p and 0xff)
    }
  }

  @Test
  fun zeroSigmaIsTheIdentity() {
    val pixels = intArrayOf(1, 2, 3, 4)
    Blur.blur(pixels, 2, 2, 0f)
    assertArrayEquals(intArrayOf(1, 2, 3, 4), pixels)
  }
}

class SourceTest {
  @Test
  fun classifiesBySchema() {
    assertEquals(SourceKind.REMOTE, Source.kindOf("https://cdn.example.com/a.jpg"))
    assertEquals(SourceKind.REMOTE, Source.kindOf("HTTP://cdn.example.com/a.jpg"))
    assertEquals(SourceKind.URI, Source.kindOf("file:///data/user/0/app/cache/a.jpg"))
    assertEquals(SourceKind.URI, Source.kindOf("content://media/external/images/1"))
    assertEquals(SourceKind.RESOURCE, Source.kindOf("ic_play"))
    assertEquals(SourceKind.RESOURCE, Source.kindOf("cover_fallback"))
  }

  @Test
  fun resizeModeParsesWithCoverDefault() {
    assertEquals(FitMode.CONTAIN, FitMode.from("contain"))
    assertEquals(FitMode.STRETCH, FitMode.from("stretch"))
    assertEquals(FitMode.CENTER, FitMode.from("center"))
    assertEquals(FitMode.COVER, FitMode.from("cover"))
    assertEquals(FitMode.COVER, FitMode.from(null))
    assertEquals(FitMode.COVER, FitMode.from("bogus"))
  }
}
