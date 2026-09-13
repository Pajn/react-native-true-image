package com.trueimage

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
  fun zeroRadiusHasNoEffect() {
    assertEquals(0f, Blur.sigmaPx(0f, 300f, 600f, 3f), 0f)
  }

  @Test
  fun scalesWithDrawScale() {
    // Same radius, same image, twice the view size → twice the sigma.
    val small = Blur.sigmaPx(20f, 300f, 600f, 3f)
    val large = Blur.sigmaPx(20f, 600f, 600f, 3f)
    assertEquals(10f, small, 0.001f)
    assertEquals(20f, large, 0.001f)
  }

  @Test
  fun unknownIntrinsicFallsBackToDensity() {
    assertEquals(60f, Blur.sigmaPx(20f, 300f, 0f, 3f), 0.001f)
  }

  @Test
  fun standInFactorNeverUpscales() {
    assertEquals(1f, Blur.standInFactor(0.5f), 0f)
    assertEquals(4f, Blur.standInFactor(8f), 0f)
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
