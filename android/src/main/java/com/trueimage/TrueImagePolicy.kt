package com.trueimage

import kotlin.math.max
import kotlin.math.min

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
   * `blurRadius` is expressed in source-image pixels so the same value blurs
   * the same picture the same way on every platform. Android blurs the view,
   * so the radius is scaled by the factor the image is drawn at. Unknown
   * intrinsic size falls back to density-independent pixels.
   */
  fun sigmaPx(radius: Float, drawnWidthPx: Float, intrinsicWidthPx: Float, density: Float): Float {
    if (radius <= 0f) return 0f
    if (intrinsicWidthPx <= 0f || drawnWidthPx <= 0f) return radius * density
    return radius * drawnWidthPx / intrinsicWidthPx
  }

  /** Downscale factor for the pre-API-31 stand-in that approximates a blur. */
  fun standInFactor(sigmaPx: Float): Float = max(1f, sigmaPx / 2f)
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
