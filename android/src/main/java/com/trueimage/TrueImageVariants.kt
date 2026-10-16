package com.trueimage

import android.content.Context
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

/**
 * cacheKey → the URLs known to hold that picture, each with its full pixel
 * size. Successful loads and prefetches with a cacheKey record here; views
 * read it to reuse a cached variant or to show a smaller one while theirs
 * loads. It holds no pixels and promises nothing about Glide's caches:
 * every variant it suggests is checked with a cache-only request, and one
 * found evicted is forgotten.
 *
 * Persisted as JSON in the app's cache directory so it outlives the
 * process, bounded to [MAX_KEYS] keys in least-recently-used order and
 * [MAX_VARIANTS] URLs per key. The file is read and written on a background
 * thread; an unreadable file is dropped and the index starts empty.
 */
object TrueImageVariants {
  const val MAX_KEYS = 2000
  const val MAX_VARIANTS = 8
  private const val FILE_NAME = "true-image-variants.json"
  private const val VERSION = 1
  private const val WRITE_DELAY_MS = 1000L

  /** One URL of a picture and that URL's full size in pixels. */
  data class Variant(val url: String, val width: Int, val height: Int) {
    val area: Long get() = width.toLong() * height
  }

  /**
   * The variants of a key split for one view: those that fill it without
   * upscaling, smallest first, and the rest, largest first.
   */
  data class Choice(val sufficient: List<Variant>, val smaller: List<Variant>)

  private val keys = object : LinkedHashMap<String, MutableList<Variant>>(64, 0.75f, true) {
    override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, MutableList<Variant>>?) = size > MAX_KEYS
  }
  private var file: File? = null
  private var writeScheduled = false
  private val executor: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { runnable ->
    Thread(runnable, "true-image-variants").apply { isDaemon = true }
  }

  /**
   * Splits [variants] for a view needing [width] × [height] pixels in
   * [mode], leaving out [exclude] (the URL the view asked for). A view
   * without a size, or in `center` mode, has no sufficient variant.
   */
  fun choose(variants: List<Variant>, exclude: String?, width: Int, height: Int, mode: FitMode): Choice {
    val others = variants.filter { it.url != exclude }
    val (sufficient, smaller) = others.partition { Variants.suffices(it.width, it.height, width, height, mode) }
    return Choice(sufficient.sortedBy { it.area }, smaller.sortedByDescending { it.area })
  }

  /** The variants recorded for [key], oldest first. Marks the key as recently used. */
  fun variants(context: Context, key: String): List<Variant> {
    attach(context)
    synchronized(this) {
      return keys[key]?.toList() ?: emptyList()
    }
  }

  /**
   * Records that [url] holds the picture [key] names, sized from the
   * drawable Glide decoded. A downsampled bitmap is scaled back to the
   * source size, since any size up to it decodes from the same data.
   */
  fun record(context: Context, key: String, url: String, drawable: Drawable) {
    val bitmap = (drawable as? BitmapDrawable)?.bitmap
    if (bitmap != null) {
      val scale = TrueImageDownsample.sourceScale(bitmap).takeIf { it > 0f } ?: 1f
      record(context, key, url, (bitmap.width / scale).roundToInt(), (bitmap.height / scale).roundToInt())
    } else {
      record(context, key, url, drawable.intrinsicWidth, drawable.intrinsicHeight)
    }
  }

  fun record(context: Context, key: String, url: String, width: Int, height: Int) {
    if (width <= 0 || height <= 0) return
    attach(context)
    synchronized(this) {
      val list = keys.getOrPut(key) { mutableListOf() }
      list.removeAll { it.url == url }
      list += Variant(url, width, height)
      while (list.size > MAX_VARIANTS) list.removeAt(0)
      scheduleWrite()
    }
  }

  /** Drops a variant a cache-only lookup could not find. */
  fun forget(context: Context, key: String, url: String) {
    attach(context)
    synchronized(this) {
      val list = keys[key] ?: return
      if (!list.removeAll { it.url == url }) return
      if (list.isEmpty()) keys.remove(key)
      scheduleWrite()
    }
  }

  /** Starts reading the persisted index, once per process. */
  private fun attach(context: Context) {
    synchronized(this) {
      if (file != null) return
      val target = File(context.applicationContext.cacheDir, FILE_NAME)
      file = target
      // Queued before any write, which is always delayed, on the same thread.
      executor.execute { read(target) }
    }
  }

  /**
   * Merges the file under what this process recorded before it landed;
   * those records are newer and win.
   */
  private fun read(target: File) {
    val loaded = try {
      if (target.exists()) parse(target.readText()) else emptyList()
    } catch (e: Exception) {
      target.delete()
      emptyList()
    }
    synchronized(this) {
      if (file !== target) return
      val recent = keys.entries.map { it.key to it.value }
      keys.clear()
      for ((key, list) in loaded) keys[key] = list.toMutableList()
      for ((key, list) in recent) {
        val merged = keys[key]?.filter { old -> list.none { it.url == old.url } }.orEmpty() + list
        keys[key] = merged.takeLast(MAX_VARIANTS).toMutableList()
      }
    }
  }

  /** Keys in least-recently-used order. Malformed entries are skipped. */
  internal fun parse(text: String): List<Pair<String, List<Variant>>> {
    val root = JSONObject(text)
    if (root.optInt("version") != VERSION) return emptyList()
    val entries = root.optJSONArray("keys") ?: return emptyList()
    val result = ArrayList<Pair<String, List<Variant>>>(entries.length())
    for (i in 0 until entries.length()) {
      val entry = entries.optJSONObject(i) ?: continue
      val key = entry.optString("key").takeIf { it.isNotEmpty() } ?: continue
      val list = entry.optJSONArray("variants") ?: continue
      val variants = (0 until list.length()).mapNotNull { j ->
        val variant = list.optJSONObject(j) ?: return@mapNotNull null
        val url = variant.optString("url").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
        val width = variant.optInt("width")
        val height = variant.optInt("height")
        if (width > 0 && height > 0) Variant(url, width, height) else null
      }
      if (variants.isNotEmpty()) result += key to variants.takeLast(MAX_VARIANTS)
    }
    return result.takeLast(MAX_KEYS)
  }

  private fun serialize(): String {
    val entries = JSONArray()
    for ((key, list) in keys) {
      val variants = JSONArray()
      for (variant in list) {
        variants.put(JSONObject().put("url", variant.url).put("width", variant.width).put("height", variant.height))
      }
      entries.put(JSONObject().put("key", key).put("variants", variants))
    }
    return JSONObject().put("version", VERSION).put("keys", entries).toString()
  }

  /** Coalesces the records of a burst, such as a prefetch batch, into one write. */
  private fun scheduleWrite() {
    if (writeScheduled || file == null) return
    writeScheduled = true
    executor.schedule({ write() }, WRITE_DELAY_MS, TimeUnit.MILLISECONDS)
  }

  /** Writes a temporary file and renames it over the index, so a crash leaves the old one whole. */
  private fun write() {
    val (target, text) = synchronized(this) {
      writeScheduled = false
      (file ?: return) to serialize()
    }
    try {
      val temporary = File(target.path + ".tmp")
      temporary.writeText(text)
      if (!temporary.renameTo(target)) {
        target.delete()
        temporary.renameTo(target)
      }
    } catch (e: Exception) {
      // The index is an optimisation; a failed write leaves the last one.
    }
  }

  /** Writes any pending change now and waits for it. */
  internal fun flush() {
    executor.submit {
      if (synchronized(this) { writeScheduled }) write()
    }.get()
  }

  /** Forgets everything in memory and re-reads the file, as a new process would. */
  internal fun reload(context: Context) {
    synchronized(this) {
      keys.clear()
      file = null
      writeScheduled = false
    }
    attach(context)
    executor.submit {}.get()
  }

  /** Empties the index and deletes its file. */
  internal fun reset(context: Context) {
    executor.submit {}.get()
    synchronized(this) {
      keys.clear()
      file = null
      writeScheduled = false
    }
    File(context.applicationContext.cacheDir, FILE_NAME).delete()
  }

  internal fun file(context: Context) = File(context.applicationContext.cacheDir, FILE_NAME)
}
