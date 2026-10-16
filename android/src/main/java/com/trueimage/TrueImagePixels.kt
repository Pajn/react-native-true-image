package com.trueimage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import com.bumptech.glide.request.FutureTarget
import android.util.Base64
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Samples an image as a small square of RGBA bytes, which JS turns into a
 * palette. The load is the view's request at the sample size, so the
 * download and disk cache are shared with views and prefetches.
 */
object TrueImagePixels {
  /** Largest sample side accepted; JS asks for far less. */
  const val MAX_SIZE = 256

  private val executor: ExecutorService = Executors.newCachedThreadPool { runnable ->
    Thread(runnable, "true-image-pixels").apply { isDaemon = true }
  }

  /**
   * Resolves base64 RGBA bytes of the image stretched to `size` × `size`, or
   * null if it could not be loaded or decoded. With a [cacheKey], a cached
   * variant of the picture is sampled instead of fetching [source]: the
   * smallest that covers the sample, else the largest. The callback runs on
   * a background thread.
   */
  fun load(
    context: Context,
    source: String,
    headers: Map<String, String>?,
    size: Int,
    cacheKey: String? = null,
    done: (String?) -> Unit,
  ) {
    if (size !in 1..MAX_SIZE) {
      done(null)
      return
    }
    executor.execute {
      val vector = TrueImageResources.vector(context, source)
      if (vector != null) {
        done(encode(rgba(vector, size)))
        return@execute
      }
      if (TrueImageRequests.model(context, source, headers) == null) {
        done(null)
        return@execute
      }
      val glide = TrueImageRequests.glide(context)
      val futures = ArrayList<FutureTarget<Drawable>>()
      // Decoded near the sample size like a view of that size would be. A
      // software bitmap, since a hardware one cannot be drawn on a Canvas.
      fun fetch(url: String, cacheOnly: Boolean): Drawable? {
        val model = TrueImageRequests.model(context, url, headers) ?: return null
        val future = TrueImageRequests.drawable(glide, model, TrueImageRequests.Size(size, size, FitMode.COVER, 1f))
          .disallowHardwareConfig()
          .onlyRetrieveFromCache(cacheOnly)
          .submit()
        futures += future
        val drawable = try {
          future.get()
        } catch (e: Exception) {
          null
        }
        if (drawable != null && cacheKey != null) TrueImageVariants.record(context, cacheKey, url, drawable)
        return drawable
      }

      var drawable: Drawable? = null
      val variants = cacheKey?.let {
        TrueImageVariants.choose(TrueImageVariants.variants(context, it), source, size, size, FitMode.COVER)
      }
      if (variants != null && (variants.sufficient.isNotEmpty() || variants.smaller.isNotEmpty())) {
        drawable = fetch(source, cacheOnly = true)
        for (variant in variants.sufficient + variants.smaller) {
          if (drawable != null) break
          drawable = fetch(variant.url, cacheOnly = true)
          if (drawable == null) TrueImageVariants.forget(context, cacheKey, variant.url)
        }
      }
      if (drawable == null) drawable = fetch(source, cacheOnly = false)
      val result = drawable?.let { encode(rgba(it, size)) }
      Handler(Looper.getMainLooper()).post { for (future in futures) glide.clear(future) }
      done(result)
    }
  }

  /** Draws a copy of the drawable stretched over `size` × `size` and reads it back. */
  fun rgba(drawable: Drawable, size: Int): ByteArray {
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    // A copy, so the cached drawable views share keeps its bounds.
    val copy = drawable.constantState?.newDrawable()?.mutate() ?: drawable
    copy.setBounds(0, 0, size, size)
    copy.draw(Canvas(bitmap))
    return rgba(bitmap).also { bitmap.recycle() }
  }

  /** Row-major RGBA bytes, not premultiplied, as `Bitmap.getPixels` reports colours. */
  fun rgba(bitmap: Bitmap): ByteArray {
    val width = bitmap.width
    val height = bitmap.height
    val colors = IntArray(width * height)
    bitmap.getPixels(colors, 0, width, 0, 0, width, height)
    val bytes = ByteArray(colors.size * 4)
    for (i in colors.indices) {
      val color = colors[i]
      bytes[i * 4] = (color ushr 16).toByte()
      bytes[i * 4 + 1] = (color ushr 8).toByte()
      bytes[i * 4 + 2] = color.toByte()
      bytes[i * 4 + 3] = (color ushr 24).toByte()
    }
    return bytes
  }

  private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
}
