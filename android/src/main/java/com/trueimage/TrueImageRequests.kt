package com.trueimage

import android.content.Context
import android.graphics.drawable.Drawable
import android.net.Uri
import com.bumptech.glide.Glide
import com.bumptech.glide.RequestBuilder
import com.bumptech.glide.RequestManager
import com.bumptech.glide.integration.okhttp3.OkHttpUrlLoader
import com.bumptech.glide.load.DecodeFormat
import com.bumptech.glide.load.model.GlideUrl
import com.bumptech.glide.load.model.Headers
import com.bumptech.glide.load.model.LazyHeaders
import com.bumptech.glide.load.resource.bitmap.DownsampleStrategy
import com.bumptech.glide.request.target.Target
import com.facebook.react.modules.network.OkHttpClientProvider
import java.io.InputStream

/**
 * A remote URL plus the headers sent with it. Identity is the URL alone, so
 * the memory cache is keyed like the disk cache and like iOS: a prefetch and
 * a view that agree on the URL share one entry whatever headers each sent.
 */
class TrueImageUrl(url: String, headers: Headers) : GlideUrl(url, headers) {
  override fun equals(other: Any?): Boolean = other is GlideUrl && other.cacheKey == cacheKey

  override fun hashCode(): Int = cacheKey.hashCode()
}

/**
 * The single place that knows how an image request is built, so that
 * `prefetch(urls)` and a view mounting later produce the identical cache
 * key and the view's load becomes a synchronous memory hit.
 */
object TrueImageRequests {
  private var registeredFor: Glide? = null

  fun glide(context: Context): RequestManager {
    val app = context.applicationContext
    registerOkHttp(app)
    return Glide.with(app)
  }

  /**
   * Routes Glide through React Native's OkHttp client so app-level network
   * configuration (interceptors, TLS, cookies) applies to images too.
   * Keyed on the Glide instance so a re-initialised Glide is set up again.
   */
  @Synchronized
  private fun registerOkHttp(context: Context) {
    val glide = Glide.get(context)
    if (registeredFor === glide) return
    registeredFor = glide
    glide.registry.replace(
      GlideUrl::class.java,
      InputStream::class.java,
      OkHttpUrlLoader.Factory(OkHttpClientProvider.getOkHttpClient()),
    )
  }

  /** http(s) → GlideUrl, scheme-less → drawable id (null if unknown), anything else → Uri. */
  fun model(context: Context, source: String, headers: Map<String, String>? = null): Any? =
    when (Source.kindOf(source)) {
      SourceKind.REMOTE -> remote(source, headers)
      SourceKind.RESOURCE -> TrueImageResources.drawableId(context, source).takeIf { it != 0 }
      SourceKind.URI -> Uri.parse(source)
    }

  private fun remote(url: String, headers: Map<String, String>?): GlideUrl {
    val builder = LazyHeaders.Builder()
    headers?.forEach { (name, value) -> builder.addHeader(name, value) }
    return TrueImageUrl(url, builder.build())
  }

  /**
   * Decodes at the image's own size. Keeping view size out of the key is what
   * makes a prefetch and a later view load share one cache entry; image URLs
   * are expected to ask the CDN for the size they need.
   */
  fun drawable(glide: RequestManager, model: Any): RequestBuilder<Drawable> =
    glide.asDrawable()
      .load(model)
      .override(Target.SIZE_ORIGINAL, Target.SIZE_ORIGINAL)
      .downsample(DownsampleStrategy.NONE)
      .format(DecodeFormat.PREFER_ARGB_8888)
      .dontTransform()
      .dontAnimate()
}
