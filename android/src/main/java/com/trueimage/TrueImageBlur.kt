package com.trueimage

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import java.util.concurrent.Executors

/**
 * Blurs an image once, off the main thread, so drawing and crossfading a
 * blurred image cost the same as a sharp one. Mirrors the iOS transformer:
 * the image is shrunk by [Blur.downscaleFactor] and blurred with the radius
 * shrunk by the same factor. The results are small, so a modest cache keeps
 * recycled rows from redoing the work.
 */
internal object TrueImageBlur {
  private val executor = Executors.newSingleThreadExecutor { runnable ->
    Thread(runnable, "TrueImage.blur").apply { priority = Thread.NORM_PRIORITY - 1 }
  }
  private val main = Handler(Looper.getMainLooper())
  private val cache = object : LruCache<String, Bitmap>(8 * 1024) {
    override fun sizeOf(key: String, value: Bitmap): Int = (value.byteCount + 1023) / 1024
  }

  /**
   * Independent of view size, so one entry serves every view of the image.
   * The tint is part of it because a tinted resource is blurred tinted.
   */
  fun key(source: String, radius: Float, factor: Float, tint: Int?): String =
    "$source|b$radius|d$factor|t${tint ?: ""}"

  fun cached(key: String): Bitmap? = cache.get(key)

  /** Tests share one process; each starts with an empty cache. */
  fun evictAll() = cache.evictAll()

  /**
   * Shrinks and blurs [drawable]; [completion] runs on the main thread with
   * the result, or null if the drawable has no size. A bitmap-backed drawable
   * is read on the worker from its immutable bitmap. Anything else is
   * rendered at the shrunk size here, on the caller's thread, since drawables
   * are not safe to draw from two threads.
   */
  fun make(drawable: Drawable, radius: Float, factor: Float, key: String, completion: (Bitmap?) -> Unit) {
    val w = drawable.intrinsicWidth
    val h = drawable.intrinsicHeight
    if (w <= 0 || h <= 0) {
      completion(null)
      return
    }
    val (sw, sh) = Blur.downscaleSize(w, h, factor)
    val sigma = radius / factor
    val source: Bitmap = (drawable as? BitmapDrawable)?.bitmap ?: render(drawable, sw, sh)
    executor.execute {
      val shrunk = shrink(source, sw, sh)
      val pixels = IntArray(sw * sh)
      shrunk.getPixels(pixels, 0, sw, 0, 0, sw, sh)
      Blur.blur(pixels, sw, sh, sigma)
      val result = if (shrunk.isMutable && shrunk !== source) shrunk else Bitmap.createBitmap(sw, sh, Bitmap.Config.ARGB_8888)
      result.setPixels(pixels, 0, sw, 0, 0, sw, sh)
      main.post {
        cache.put(key, result)
        completion(result)
      }
    }
  }

  private fun render(drawable: Drawable, w: Int, h: Int): Bitmap {
    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    drawable.setBounds(0, 0, w, h)
    drawable.alpha = 255
    drawable.draw(Canvas(bitmap))
    return bitmap
  }

  /**
   * Halves the bitmap until it is within 2x of the target, then scales the
   * rest. Each bilinear halving averages a 2x2 block, so the whole chain is
   * a box filter; a single bilinear jump would sample four source pixels
   * per output pixel and alias.
   */
  private fun shrink(source: Bitmap, w: Int, h: Int): Bitmap {
    var current = source
    while (current.width >= 2 * w && current.height >= 2 * h) {
      current = Bitmap.createScaledBitmap(current, current.width / 2, current.height / 2, true)
    }
    if (current.width == w && current.height == h && current !== source) return current
    return Bitmap.createScaledBitmap(current, w, h, true)
  }
}
