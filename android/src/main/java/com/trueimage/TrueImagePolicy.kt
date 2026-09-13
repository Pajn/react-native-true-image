package com.trueimage

import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Pure geometry and policy shared by the view and the unit tests.
 * Nothing in this file touches the Android framework.
 */
enum class FitMode {
  COVER, CONTAIN, STRETCH, CENTER;

  companion object {
    fun from(value: String?): FitMode = when (value) {
      "contain" -> CONTAIN
      "stretch" -> STRETCH
      "center" -> CENTER
      else -> COVER
    }
  }
}

data class FitRect(val left: Float, val top: Float, val width: Float, val height: Float) {
  val right: Float get() = left + width
  val bottom: Float get() = top + height
}

object Fit {
  /**
   * The rect an image of the given intrinsic size occupies inside the bounds.
   * COVER overflows, CONTAIN insets, both are centred. STRETCH fills the
   * bounds, CENTER draws at intrinsic size. A degenerate intrinsic size
   * falls back to the full bounds.
   */
  fun rect(boundsW: Float, boundsH: Float, intrinsicW: Float, intrinsicH: Float, mode: FitMode): FitRect {
    val full = FitRect(0f, 0f, boundsW, boundsH)
    if (intrinsicW <= 0f || intrinsicH <= 0f || boundsW <= 0f || boundsH <= 0f) return full
    val (w, h) = when (mode) {
      FitMode.STRETCH -> return full
      FitMode.CENTER -> intrinsicW to intrinsicH
      FitMode.COVER, FitMode.CONTAIN -> {
        val sx = boundsW / intrinsicW
        val sy = boundsH / intrinsicH
        val scale = if (mode == FitMode.COVER) max(sx, sy) else min(sx, sy)
        intrinsicW * scale to intrinsicH * scale
      }
    }
    return FitRect((boundsW - w) / 2f, (boundsH - h) / 2f, w, h)
  }
}

/**
 * Linear alpha ramp for the incoming image. The outgoing image is drawn at
 * the complementary alpha. Starting above zero lets an image whose fade-in
 * was interrupted carry on from where it was instead of jumping.
 */
class Crossfade(
  private val durationMs: Long,
  private val startTimeMs: Long,
  private val startAlpha: Float = 0f,
) {
  fun alpha(nowMs: Long): Float {
    if (durationMs <= 0L) return 1f
    val t = ((nowMs - startTimeMs).toFloat() / durationMs).coerceIn(0f, 1f)
    return (startAlpha + (1f - startAlpha) * t).coerceIn(0f, 1f)
  }

  fun isDone(nowMs: Long): Boolean = alpha(nowMs) >= 1f
}

object Blur {
  /**
   * Pixels the blur radius spans after the pre-blur shrink when
   * `blurPixelsPerRadius` is omitted. The same default as iOS.
   */
  const val DEFAULT_PIXELS_PER_RADIUS = 2f

  /**
   * Factor to shrink an image by before blurring it. A Gaussian blur removes
   * every detail finer than its radius, so blurring a copy shrunk until the
   * radius spans [pixelsPerRadius] pixels looks the same and costs a small
   * fraction as much. 1 (no shrink) for a radius already that small, or when
   * [pixelsPerRadius] is zero or negative, which disables the shrink.
   */
  fun downscaleFactor(radius: Float, pixelsPerRadius: Float): Float {
    if (radius <= 0f || pixelsPerRadius <= 0f) return 1f
    return max(1f, radius / pixelsPerRadius)
  }

  /** The size shrunk by [factor], rounded up and never below one pixel. */
  fun downscaleSize(width: Int, height: Int, factor: Float): Pair<Int, Int> {
    if (factor <= 1f) return width to height
    return max(1, ceil(width / factor).toInt()) to max(1, ceil(height / factor).toInt())
  }

  /**
   * Width of each of the three box passes that approximate a Gaussian of
   * [sigma]. The same formula as the iOS blur, so one radius looks the same
   * on both platforms. Always odd; 0 means no blur.
   */
  fun boxSize(sigma: Float): Int {
    if (sigma <= 0f) return 0
    var size = floor(sigma * 3f * sqrt(2f * PI.toFloat()) / 4f + 0.5f).toInt()
    if (size % 2 == 0) size++
    return max(1, size)
  }

  /**
   * Gaussian blur of non-premultiplied ARGB pixels in place, as three box
   * passes per axis with edge pixels extended. Blurs premultiplied colour so
   * transparent pixels do not bleed their colour into their neighbours. Runs
   * in time proportional to the pixel count whatever the sigma.
   */
  fun blur(pixels: IntArray, width: Int, height: Int, sigma: Float) {
    val box = boxSize(sigma)
    if (box <= 1 || width <= 0 || height <= 0) return
    val n = width * height
    val a = IntArray(n)
    val r = IntArray(n)
    val g = IntArray(n)
    val b = IntArray(n)
    for (i in 0 until n) {
      val p = pixels[i]
      val alpha = (p ushr 24) and 0xff
      a[i] = alpha
      r[i] = ((p ushr 16) and 0xff) * alpha / 255
      g[i] = ((p ushr 8) and 0xff) * alpha / 255
      b[i] = (p and 0xff) * alpha / 255
    }
    val scratch = IntArray(n)
    for (channel in arrayOf(a, r, g, b)) {
      repeat(3) {
        boxRows(channel, scratch, width, height, box)
        boxColumns(scratch, channel, width, height, box)
      }
    }
    for (i in 0 until n) {
      val alpha = a[i]
      if (alpha == 0) {
        pixels[i] = 0
        continue
      }
      val red = min(255, r[i] * 255 / alpha)
      val green = min(255, g[i] * 255 / alpha)
      val blue = min(255, b[i] * 255 / alpha)
      pixels[i] = (alpha shl 24) or (red shl 16) or (green shl 8) or blue
    }
  }

  private fun boxRows(src: IntArray, dst: IntArray, width: Int, height: Int, box: Int) {
    val radius = box / 2
    for (y in 0 until height) {
      val row = y * width
      var sum = 0
      for (k in -radius..radius) sum += src[row + k.coerceIn(0, width - 1)]
      for (x in 0 until width) {
        dst[row + x] = (sum + box / 2) / box
        sum += src[row + (x + radius + 1).coerceIn(0, width - 1)] - src[row + (x - radius).coerceIn(0, width - 1)]
      }
    }
  }

  private fun boxColumns(src: IntArray, dst: IntArray, width: Int, height: Int, box: Int) {
    val radius = box / 2
    for (x in 0 until width) {
      var sum = 0
      for (k in -radius..radius) sum += src[k.coerceIn(0, height - 1) * width + x]
      for (y in 0 until height) {
        dst[y * width + x] = (sum + box / 2) / box
        sum += src[(y + radius + 1).coerceIn(0, height - 1) * width + x] -
          src[(y - radius).coerceIn(0, height - 1) * width + x]
      }
    }
  }
}

enum class SourceKind { REMOTE, RESOURCE, URI }

object Source {
  private val scheme = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:")

  /** The scheme is the discriminator: none means a native resource name. */
  fun kindOf(source: String): SourceKind {
    val match = scheme.find(source) ?: return SourceKind.RESOURCE
    return when (match.value.lowercase()) {
      "http:", "https:" -> SourceKind.REMOTE
      else -> SourceKind.URI
    }
  }
}
