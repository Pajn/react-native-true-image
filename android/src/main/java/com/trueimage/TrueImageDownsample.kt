package com.trueimage

import android.graphics.Bitmap
import com.bumptech.glide.load.engine.bitmap_recycle.BitmapPool
import com.bumptech.glide.load.resource.bitmap.BitmapTransformation
import com.bumptech.glide.load.resource.bitmap.DownsampleStrategy
import java.security.MessageDigest
import java.util.WeakHashMap
import kotlin.math.max
import kotlin.math.min

/** Linear scale policy, evaluated by Glide before allocating the decoded bitmap. */
data class TrueImageDownsample(val mode: FitMode, val threshold: Float) : DownsampleStrategy() {
  private var sourceWidth = 0
  private var sourceHeight = 0

  override fun getScaleFactor(sourceWidth: Int, sourceHeight: Int, requestedWidth: Int, requestedHeight: Int): Float {
    this.sourceWidth = max(this.sourceWidth, sourceWidth)
    this.sourceHeight = max(this.sourceHeight, sourceHeight)
    if (mode == FitMode.CENTER || threshold <= 0f || requestedWidth <= 0 || requestedHeight <= 0) return 1f
    val sx = requestedWidth.toFloat() / sourceWidth
    val sy = requestedHeight.toFloat() / sourceHeight
    // Stretch keeps enough detail on both axes; the canvas stretches at draw time.
    val scale = if (mode == FitMode.CONTAIN) min(sx, sy) else max(sx, sy)
    return if (scale < 1f / threshold) scale else 1f
  }

  override fun getSampleSizeRounding(sourceWidth: Int, sourceHeight: Int, requestedWidth: Int, requestedHeight: Int) =
    SampleSizeRounding.QUALITY

  /** Preserve source-pixel blur semantics after the decoder has reduced the bitmap. */
  class Metadata(private val strategy: TrueImageDownsample) : BitmapTransformation() {
    override fun transform(pool: BitmapPool, toTransform: Bitmap, outWidth: Int, outHeight: Int): Bitmap {
      val sourceLong = max(strategy.sourceWidth, strategy.sourceHeight)
      val scale = if (sourceLong > 0) max(toTransform.width, toTransform.height).toFloat() / sourceLong else 1f
      synchronized(scales) { scales[toTransform] = scale }
      return toTransform
    }

    override fun equals(other: Any?) = other is Metadata && strategy == other.strategy
    override fun hashCode() = strategy.hashCode()
    override fun updateDiskCacheKey(messageDigest: MessageDigest) {
      messageDigest.update("true-image-downsample-v1:$strategy".toByteArray(Charsets.UTF_8))
    }
  }

  companion object {
    private val scales = WeakHashMap<Bitmap, Float>()
    fun sourceScale(bitmap: Bitmap): Float = synchronized(scales) { scales[bitmap] ?: 1f }
  }
}
