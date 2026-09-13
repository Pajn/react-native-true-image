package com.trueimage

import android.app.Application
import android.graphics.drawable.Drawable
import android.os.Looper
import com.bumptech.glide.Glide
import com.bumptech.glide.GlideBuilder
import com.bumptech.glide.Priority
import com.bumptech.glide.RequestBuilder
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.Options
import com.bumptech.glide.load.data.DataFetcher
import com.bumptech.glide.load.engine.cache.DiskCache
import com.bumptech.glide.load.engine.executor.GlideExecutor
import com.bumptech.glide.load.model.GlideUrl
import com.bumptech.glide.load.model.ModelLoader
import com.bumptech.glide.load.model.ModelLoaderFactory
import com.bumptech.glide.load.model.MultiModelLoaderFactory
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import com.bumptech.glide.signature.ObjectKey
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import java.util.zip.CRC32
import java.util.zip.Deflater
import java.util.concurrent.atomic.AtomicReference
import org.junit.After
import org.junit.Before
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/**
 * Glide with single-thread executors and a fake network, so every load is
 * deterministic and each fetch can be counted, failed or held.
 */
abstract class GlideTestCase {
  lateinit var app: Application
  lateinit var network: FakeNetwork

  @Before
  fun setUpGlide() {
    app = RuntimeEnvironment.getApplication()
    Glide.init(
      app,
      GlideBuilder()
        .setSourceExecutor(GlideExecutor.newSourceBuilder().setThreadCount(1).build())
        .setDiskCacheExecutor(GlideExecutor.newDiskCacheBuilder().setThreadCount(1).build())
        // No disk tier: a hit is a memory hit or nothing.
        .setDiskCache(DiskCache.Factory { null }),
    )
    // Registers the OkHttp loader on this instance; the fake then replaces it.
    TrueImageRequests.glide(app)
    network = FakeNetwork()
    Glide.get(app).registry.replace(GlideUrl::class.java, InputStream::class.java, network.Factory())
    TrueImageBlur.evictAll()
  }

  @After
  fun tearDownGlide() {
    Glide.tearDown()
  }

  /**
   * Lets Glide's worker threads finish and runs everything they posted back
   * to the main thread. Returns as soon as the main queue has stayed empty
   * for a short while after background work settled.
   */
  fun settle(until: (() -> Boolean)? = null) {
    val deadline = System.currentTimeMillis() + 5_000
    var quietRounds = 0
    while (System.currentTimeMillis() < deadline) {
      val looper = shadowOf(Looper.getMainLooper())
      if (looper.isIdle) quietRounds++ else { quietRounds = 0; looper.idle() }
      if (until != null) {
        if (until()) return
      } else if (quietRounds >= 5) {
        return
      }
      Thread.sleep(20)
    }
  }

  /** Loads through a bare target; null if the load failed. */
  fun loadSync(builder: RequestBuilder<Drawable>): Drawable? {
    var result: Drawable? = null
    var failed = false
    val target = object : CustomTarget<Drawable>() {
      override fun onResourceReady(resource: Drawable, transition: Transition<in Drawable>?) {
        result = resource
      }

      override fun onLoadFailed(errorDrawable: Drawable?) {
        failed = true
      }

      override fun onLoadCleared(placeholder: Drawable?) = Unit
    }
    builder.into(target)
    settle { result != null || failed }
    return result
  }

  /** Accepts URL strings and [TrueImagePrefetcher.Request]s. */
  fun prefetch(vararg sources: Any): Boolean {
    val requests = sources.map {
      when (it) {
        is String -> TrueImagePrefetcher.Request(it)
        is TrueImagePrefetcher.Request -> it
        else -> error("unsupported prefetch source $it")
      }
    }
    val result = AtomicReference<Boolean?>(null)
    TrueImagePrefetcher.prefetch(app, requests) { result.set(it) }
    settle { result.get() != null }
    // Let the batch's single main-thread post (the target clears) run.
    settle()
    return result.get() ?: error("prefetch did not complete")
  }

  class FakeNetwork {
    val fetches = java.util.concurrent.ConcurrentHashMap<String, Int>()
    /** Headers Glide carried on the last request per URL. */
    val headersSeen = mutableMapOf<String, Map<String, String>>()
    val failOnce = mutableSetOf<String>()
    val failAlways = mutableSetOf<String>()
    /** URLs whose fetch is held until [release]. */
    val hang = mutableSetOf<String>()
    private val held = mutableMapOf<String, DataFetcher.DataCallback<in InputStream>>()

    fun release(url: String) {
      held.remove(url)?.onDataReady(ByteArrayInputStream(PNG))
    }

    inner class Factory : ModelLoaderFactory<GlideUrl, InputStream> {
      override fun build(multiFactory: MultiModelLoaderFactory): ModelLoader<GlideUrl, InputStream> = Loader()

      override fun teardown() = Unit
    }

    inner class Loader : ModelLoader<GlideUrl, InputStream> {
      override fun buildLoadData(model: GlideUrl, width: Int, height: Int, options: Options): ModelLoader.LoadData<InputStream> {
        headersSeen[model.toStringUrl()] = model.headers
        return ModelLoader.LoadData(ObjectKey(model.toStringUrl()), Fetcher(model.toStringUrl()))
      }

      override fun handles(model: GlideUrl) = true
    }

    inner class Fetcher(private val url: String) : DataFetcher<InputStream> {
      override fun loadData(priority: Priority, callback: DataFetcher.DataCallback<in InputStream>) {
        fetches[url] = (fetches[url] ?: 0) + 1
        when {
          url in hang -> held[url] = callback
          url in failAlways || failOnce.remove(url) -> callback.onLoadFailed(IOException("HTTP 404"))
          else -> callback.onDataReady(ByteArrayInputStream(PNG))
        }
      }

      override fun cleanup() = Unit

      override fun cancel() = Unit

      override fun getDataClass(): Class<InputStream> = InputStream::class.java

      override fun getDataSource(): DataSource = DataSource.REMOTE
    }
  }

  companion object {
    /** An 8x8 opaque red PNG built in code so no test resource lookup is needed. */
    val PNG: ByteArray = png(8, 8)

    private fun png(width: Int, height: Int): ByteArray {
      val raw = ByteArrayOutputStream()
      repeat(height) {
        raw.write(0) // filter: none
        repeat(width) { raw.write(byteArrayOf(200.toByte(), 50, 50, 255.toByte())) }
      }
      val deflater = Deflater()
      deflater.setInput(raw.toByteArray())
      deflater.finish()
      val compressed = ByteArrayOutputStream()
      val buffer = ByteArray(4096)
      while (!deflater.finished()) compressed.write(buffer, 0, deflater.deflate(buffer))

      fun chunk(type: String, data: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        val typeBytes = type.toByteArray(Charsets.US_ASCII)
        out.write(ByteBuffer.allocate(4).putInt(data.size).array())
        out.write(typeBytes)
        out.write(data)
        val crc = CRC32()
        crc.update(typeBytes)
        crc.update(data)
        out.write(ByteBuffer.allocate(4).putInt(crc.value.toInt()).array())
        return out.toByteArray()
      }

      val header = ByteBuffer.allocate(13)
        .putInt(width).putInt(height)
        .put(8) // bit depth
        .put(6) // colour type: RGBA
        .put(0).put(0).put(0)
        .array()
      val out = ByteArrayOutputStream()
      out.write(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
      out.write(chunk("IHDR", header))
      out.write(chunk("IDAT", compressed.toByteArray()))
      out.write(chunk("IEND", ByteArray(0)))
      return out.toByteArray()
    }
  }
}
