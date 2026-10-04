package com.trueimage

import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.min

/** A bounded index of Glide-owned variants. It never retains bitmap memory. */
object TrueImageDecodeCache {
  private data class Key(val source: String, val size: TrueImageRequests.Size)
  private data class Entry(val bitmap: WeakReference<Bitmap>, val width: Int, val height: Int, val original: Boolean)
  private val entries = object : LinkedHashMap<Key, Entry>(256, 0.75f, true) {
    override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Key, Entry>?) = size > 256
  }

  @Synchronized
  fun record(source: String, size: TrueImageRequests.Size, drawable: Drawable) {
    val bitmap = (drawable as? BitmapDrawable)?.bitmap ?: return
    if (!size.enabled) return
    entries[Key(source, size)] = Entry(WeakReference(bitmap), bitmap.width, bitmap.height,
      TrueImageDownsample.sourceScale(bitmap) >= 0.999f)
  }

  @Synchronized
  fun compatible(source: String, wanted: TrueImageRequests.Size): TrueImageRequests.Size {
    if (!wanted.enabled) return wanted
    return entries.entries.lastOrNull { (key, entry) ->
      val bitmap = entry.bitmap.get()
      if (key.source != source || key.size.mode != wanted.mode || key.size.threshold != wanted.threshold ||
          bitmap == null || bitmap.isRecycled) return@lastOrNull false
      val sx = wanted.width.toFloat() / entry.width
      val sy = wanted.height.toFloat() / entry.height
      val scale = if (wanted.mode == FitMode.CONTAIN) min(sx, sy) else max(sx, sy)
      // Never upscale a reduced variant. A full-resolution source cannot provide more detail.
      (scale <= 1f || entry.original) && scale >= 1f / wanted.threshold
    }?.key?.size ?: wanted
  }
}
