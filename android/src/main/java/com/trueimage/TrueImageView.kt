
  internal val previousAlpha: Int? get() = previous?.display?.alphapackage com.trueimage

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PaintFlagsDrawFilter
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.view.View
import android.view.animation.AnimationUtils
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.engine.GlideException
import com.bumptech.glide.request.RequestListener
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.target.Target
import com.bumptech.glide.request.transition.Transition
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.BackgroundStyleApplicator
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import kotlin.math.roundToInt

/**
 * One view, one canvas, one image (two during a crossfade). No child views
 * and no placeholders: that is the performance premise of the whole module.
 * Props are set by the view manager and applied together in [commit].
 */
class TrueImageView(context: Context) : View(context) {
  // MARK: Props

  var source: String? = null
  /** Sent with remote requests. Not part of the cache key. */
  var headers: Map<String, String>? = null
  var fitMode: FitMode = FitMode.COVER
  /** Fade duration in milliseconds. */
  var transitionMs: Int = 0
  /** In source-image pixels. */
  var blurRadius: Float = 0f
  /** Pixels the blur radius spans after the pre-blur shrink; 0 blurs at full size. */
  var blurPixelsPerRadius: Float = Blur.DEFAULT_PIXELS_PER_RADIUS
  var tintColor: Int? = null
  var recyclingKey: String? = null
  /** Shown into an empty view until [source] loads. Never fades in, reports nothing. */
  var placeholder: String? = null
  var placeholderHeaders: Map<String, String>? = null
  /** Crossfade from the placeholder to the image, in milliseconds. 0 cuts. */
  var placeholderTransitionMs: Int = 0
  /** Whether a remote placeholder may be fetched; off, it shows only when cached. */
  var placeholderFromNetwork: Boolean = false

  // MARK: State

  private data class Request(val source: String)

  /**
   * One image and the Glide target that owns its bitmap. A blurred image
   * keeps the sharp original as the source for re-blurs and as the size the
   * fit is computed from; [blurred] is what gets drawn.
   */
  private class Layer(val request: Request, val fromResource: Boolean, val isPlaceholder: Boolean = false) {
    var drawable: Drawable? = null
    var target: Target<Drawable>? = null
    var fromMemory = false
    var blurred: Drawable? = null
    var blurKey: String? = null

    val display: Drawable? get() = blurred ?: drawable
  }

  private var current: Layer? = null
  private var previous: Layer? = null
  private var pending: Layer? = null
  private var pendingPlaceholder: Layer? = null
  private var crossfade: Crossfade? = null
  /** True while the running crossfade is a fade-in over an empty view. */
  private var fadeFromEmpty = false
  private var appliedRecyclingKey: String? = null
  private var appliedFitMode = FitMode.COVER
  private var appliedTint: Int? = null
  private var appliedBlur = 0f
  private var appliedBlurPixelsPerRadius = Blur.DEFAULT_PIXELS_PER_RADIUS
  private var appliedPlaceholder: String? = null

  private val filter = PaintFlagsDrawFilter(0, Paint.FILTER_BITMAP_FLAG)

  /** Tests observe events here instead of through the React event dispatcher. */
  internal var eventSink: ((name: String, payload: Map<String, Any>) -> Unit)? = null

  internal val hasImage: Boolean get() = current?.drawable != null
  internal val isCrossfading: Boolean get() = crossfade != null
  internal val hasPendingLoad: Boolean get() = pending != null
  internal val currentDrawable: Drawable? get() = current?.drawable
  internal val currentBlurred: Drawable? get() = current?.blurred
  internal val isShowingPlaceholder: Boolean get() = current?.isPlaceholder == true
  internal val fadeAlpha: Float? get() = crossfade?.alpha(now())

  init {
    setWillNotDraw(false)
  }

  // MARK: View manager entry points

  /**
   * Applies every prop set since the last commit. Runs inside the props
   * transaction, so a recycling key change clears the view before the new
   * source loads and the two never crossfade into each other.
   */
  fun commit() {
    if (recyclingKey != appliedRecyclingKey) {
      appliedRecyclingKey = recyclingKey
      clear()
    }
    if (fitMode != appliedFitMode) {
      appliedFitMode = fitMode
      invalidate()
    }
    if (tintColor != appliedTint) {
      appliedTint = tintColor
      applyTint(current)
      applyTint(previous)
      current?.let { if (it.blurred != null) reblur(it) }
      invalidate()
    }
    if (blurRadius != appliedBlur || blurPixelsPerRadius != appliedBlurPixelsPerRadius) {
      appliedBlur = blurRadius
      appliedBlurPixelsPerRadius = blurPixelsPerRadius
      current?.let { reblur(it) }
    }

    val placeholderChanged = placeholder != appliedPlaceholder
    appliedPlaceholder = placeholder

    val src = source
    if (src.isNullOrEmpty()) {
      clear()
      return
    }
    val request = Request(src)
    current?.let {
      if (!it.isPlaceholder && it.request == request) {
        cancelPending()
        return
      }
    }
    if (pending?.request == request) {
      if (placeholderChanged) loadPlaceholder()
      return
    }
    load(request)
  }

  /** Called when the view manager drops the view. Nothing may run after this. */
  fun release() {
    cancelPending()
    crossfade = null
    releaseLayer(previous)
    releaseLayer(current)
    previous = null
    current = null
  }

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    // A recycling key may have cleared this view while it was detached.
    val src = source
    if (src != null && current == null && pending == null) load(Request(src))
  }

  // MARK: Loading

  private fun load(request: Request) {
    cancelPending()

    val vector = TrueImageResources.vector(context, request.source)
    if (vector != null) {
      val layer = Layer(request, fromResource = true)
      layer.drawable = vector.mutate()
      layer.fromMemory = true
      pending = layer
      present(layer)
      return
    }

    val model = TrueImageRequests.model(context, request.source, headers)
    if (model == null) {
      clear()
      emitError("No drawable named \"${request.source}\"", request.source)
      return
    }

    val layer = Layer(request, fromResource = model is Int)
    val target = object : CustomTarget<Drawable>() {
      override fun onResourceReady(resource: Drawable, transition: Transition<in Drawable>?) {
        // A stale target (superseded by a newer source) is silent.
        if (pending !== layer) return
        // Two views sharing one cached drawable must not share alpha.
        layer.drawable = resource.mutate()
        present(layer)
      }

      override fun onLoadFailed(errorDrawable: Drawable?) {
        if (pending !== layer) return
        pending = null
        emitError("Failed to load image", request.source)
      }

      override fun onLoadCleared(placeholder: Drawable?) {
        layer.drawable = null
        invalidate()
      }
    }
    layer.target = target
    pending = layer

    val listener = object : RequestListener<Drawable> {
      override fun onResourceReady(
        resource: Drawable,
        model: Any,
        target: Target<Drawable>?,
        dataSource: DataSource,
        isFirstResource: Boolean,
      ): Boolean {
        layer.fromMemory = dataSource == DataSource.MEMORY_CACHE
        return false
      }

      override fun onLoadFailed(
        e: GlideException?,
        model: Any?,
        target: Target<Drawable>,
        isFirstResource: Boolean,
      ): Boolean = false
    }

    // A memory hit is delivered synchronously inside into().
    TrueImageRequests.drawable(TrueImageRequests.glide(context), model)
      .listener(listener)
      .into(target)
    // Only an empty view gets a placeholder; a displayed image stays up
    // until its replacement arrives.
    if (current == null && pending === layer) loadPlaceholder()
  }

  /**
   * Loads the placeholder for a pending source into an empty view. One
   * already showing is kept. A remote placeholder is answered from Glide's
   * caches unless it may hit the network. Silent on failure.
   */
  private fun loadPlaceholder() {
    cancelPendingPlaceholder()
    val src = placeholder
    if (src.isNullOrEmpty()) {
      current?.let { if (it.isPlaceholder) { releaseLayer(it); current = null; invalidate() } }
      return
    }
    current?.let { if (it.isPlaceholder && it.request.source == src) return }
    val request = Request(src)

    val vector = TrueImageResources.vector(context, src)
    if (vector != null) {
      val layer = Layer(request, fromResource = true, isPlaceholder = true)
      layer.drawable = vector.mutate()
      pendingPlaceholder = layer
      presentPlaceholder(layer)
      return
    }
    val model = TrueImageRequests.model(context, src, placeholderHeaders) ?: return
    val layer = Layer(request, fromResource = model is Int, isPlaceholder = true)
    val target = object : CustomTarget<Drawable>() {
      override fun onResourceReady(resource: Drawable, transition: Transition<in Drawable>?) {
        if (pendingPlaceholder !== layer) return
        layer.drawable = resource.mutate()
        presentPlaceholder(layer)
      }

      override fun onLoadFailed(errorDrawable: Drawable?) {
        if (pendingPlaceholder === layer) pendingPlaceholder = null
      }

      override fun onLoadCleared(placeholder: Drawable?) {
        layer.drawable = null
        invalidate()
      }
    }
    layer.target = target
    pendingPlaceholder = layer
    val cacheOnly = !placeholderFromNetwork && Source.kindOf(src) == SourceKind.REMOTE
    TrueImageRequests.drawable(TrueImageRequests.glide(context), model)
      .onlyRetrieveFromCache(cacheOnly)
      .into(target)
  }

  private fun cancelPending() {
    cancelPendingPlaceholder()
    val layer = pending ?: return
    pending = null
    releaseLayer(layer)
  }

  private fun cancelPendingPlaceholder() {
    val layer = pendingPlaceholder ?: return
    pendingPlaceholder = null
    releaseLayer(layer)
  }

  private fun releaseLayer(layer: Layer?) {
    if (layer == null) return
    layer.drawable = null
    layer.target?.let { TrueImageRequests.glide(context).clear(it) }
    layer.target = null
  }

  private fun clear() {
    cancelPending()
    crossfade = null
    releaseLayer(previous)
    releaseLayer(current)
    previous = null
    current = null
    invalidate()
  }

  // MARK: Display

  /**
   * Shows a loaded layer, blurring it first when a blur is set. The blurred
   * copy is what appears; the sharp original never draws, so a blurred image
   * arriving late never flashes sharp. The layer stays pending until then so
   * a newer source cancels it.
   */
  private fun present(layer: Layer) {
    val drawable = layer.drawable ?: return
    applyTint(layer)
    if (blurRadius <= 0f) {
      pending = null
      show(layer)
      return
    }
    val factor = Blur.downscaleFactor(blurRadius, blurPixelsPerRadius)
    val key = TrueImageBlur.key(layer.request.source, blurRadius, factor, tintOf(layer))
    TrueImageBlur.cached(key)?.let {
      layer.blurred = BitmapDrawable(resources, it)
      layer.blurKey = key
      pending = null
      show(layer)
      return
    }
    TrueImageBlur.make(drawable, blurRadius, factor, key) { bitmap ->
      if (pending !== layer) return@make
      pending = null
      if (bitmap != null) {
        layer.blurred = BitmapDrawable(resources, bitmap)
        layer.blurKey = key
      }
      show(layer)
    }
  }

  /** The placeholder path of [present]: blur if set, then show without events. */
  private fun presentPlaceholder(layer: Layer) {
    val drawable = layer.drawable ?: return
    applyTint(layer)
    if (blurRadius <= 0f) {
      showPlaceholder(layer)
      return
    }
    val factor = Blur.downscaleFactor(blurRadius, blurPixelsPerRadius)
    val key = TrueImageBlur.key(layer.request.source, blurRadius, factor, tintOf(layer))
    TrueImageBlur.cached(key)?.let {
      layer.blurred = BitmapDrawable(resources, it)
      layer.blurKey = key
      showPlaceholder(layer)
      return
    }
    TrueImageBlur.make(drawable, blurRadius, factor, key) { bitmap ->
      if (pendingPlaceholder !== layer) return@make
      if (bitmap != null) {
        layer.blurred = BitmapDrawable(resources, bitmap)
        layer.blurKey = key
      }
      showPlaceholder(layer)
    }
  }

  /**
   * A placeholder draws at once and only into a view that is still empty
   * and still waiting; if the image got there first it is dropped unseen.
   */
  private fun showPlaceholder(layer: Layer) {
    pendingPlaceholder = null
    if (current != null || pending == null) {
      releaseLayer(layer)
      return
    }
    crossfade = null
    current = layer
    layer.display?.alpha = 255
    invalidate()
  }

  /**
   * A blur change on a displayed image re-blurs the sharp original it kept.
   * The old blur stays up until the new one is ready; only clearing the blur
   * switches at once, since the sharp image is already there.
   */
  private fun reblur(layer: Layer) {
    val drawable = layer.drawable ?: return
    if (blurRadius <= 0f) {
      layer.blurred = null
      layer.blurKey = null
      invalidate()
      return
    }
    val factor = Blur.downscaleFactor(blurRadius, blurPixelsPerRadius)
    val key = TrueImageBlur.key(layer.request.source, blurRadius, factor, tintOf(layer))
    if (key == layer.blurKey) return
    TrueImageBlur.cached(key)?.let {
      layer.blurred = BitmapDrawable(resources, it)
      layer.blurKey = key
      invalidate()
      return
    }
    TrueImageBlur.make(drawable, blurRadius, factor, key) { bitmap ->
      // Stale if the image changed, or a later blur change already landed.
      if (current !== layer || bitmap == null) return@make
      val wanted = TrueImageBlur.key(
        layer.request.source, blurRadius, Blur.downscaleFactor(blurRadius, blurPixelsPerRadius), tintOf(layer),
      )
      if (wanted != key) return@make
      layer.blurred = BitmapDrawable(resources, bitmap)
      layer.blurKey = key
      invalidate()
    }
  }

  private fun show(layer: Layer) {
    val drawable = layer.drawable ?: return
    cancelPendingPlaceholder()
    val hasContent = current?.drawable != null
    // Leaving a placeholder is its own transition; it is never a late arrival.
    val duration = if (current?.isPlaceholder == true) placeholderTransitionMs else transitionMs
    val fade = duration > 0 && !layer.fromResource && !(layer.fromMemory && !hasContent)
    applyTint(layer)

    val now = now()
    val interrupted = crossfade
    val interruptedAlpha = interrupted?.alpha(now) ?: 0f
    val interruptedFromEmpty = interrupted != null && fadeFromEmpty

    emitLoad(drawable.intrinsicWidth, drawable.intrinsicHeight, layer.request.source)

    releaseLayer(previous)
    previous = null
    var startAlpha = 0f
    if (fade && hasContent) {
      if (interruptedFromEmpty) {
        // The view as a whole carries on from where the interrupted fade-in
        // was; the new image simply takes over the pixels at that alpha.
        releaseLayer(current)
        startAlpha = interruptedAlpha
      } else {
        previous = current
      }
    } else {
      releaseLayer(current)
    }
    current = layer

    if (fade) {
      // The interrupted crossfade never completes, so it never reports
      // onDisplayEnd; this one reports in its turn.
      crossfade = Crossfade(duration.toLong(), now, startAlpha)
      fadeFromEmpty = previous == null
      emitDisplay()
      postInvalidateOnAnimation()
    } else {
      crossfade = null
      layer.display?.alpha = 255
      emitDisplay()
      emitDisplayEnd()
      invalidate()
    }
  }

  /** Tints apply to native resources only, so only their blur keys carry one. */
  private fun tintOf(layer: Layer): Int? = if (layer.fromResource) tintColor else null

  private fun applyTint(layer: Layer?) {
    val drawable = layer?.drawable ?: return
    // Tints apply to native resources only; remote bitmaps are never tinted.
    if (!layer.fromResource) return
    val tint = tintColor
    if (tint != null) drawable.setTint(tint) else drawable.setTintList(null)
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    BackgroundStyleApplicator.clipToPaddingBox(this, canvas)
    canvas.drawFilter = filter

    val fade = crossfade
    val now = now()
    val alpha = fade?.alpha(now) ?: 1f

    // The outgoing image stays fully opaque under the incoming one. Drawing
    // it at the complementary alpha would dip the composite to 75 % coverage
    // mid-fade and let the background through.
    previous?.let { draw(canvas, it, 1f) }
    current?.let { draw(canvas, it, alpha) }

    if (fade != null) {
      if (fade.isDone(now)) {
        crossfade = null
        releaseLayer(previous)
        previous = null
        emitDisplayEnd()
      } else {
        postInvalidateOnAnimation()
      }
    }
  }

  /** The fit comes from the sharp original's size; a blurred copy is stretched into the same rect. */
  private fun draw(canvas: Canvas, layer: Layer, alpha: Float) {
    val source = layer.drawable ?: return
    val drawable = layer.display ?: return
    val rect = Fit.rect(
      width.toFloat(), height.toFloat(),
      source.intrinsicWidth.toFloat(), source.intrinsicHeight.toFloat(),
      fitMode,
    )
    drawable.setBounds(
      rect.left.roundToInt(), rect.top.roundToInt(),
      rect.right.roundToInt(), rect.bottom.roundToInt(),
    )
    drawable.alpha = (alpha.coerceIn(0f, 1f) * 255f).roundToInt()
    drawable.draw(canvas)
  }

  // MARK: Events

  private fun emitLoad(width: Int, height: Int, source: String) =
    emit("topLoad", mapOf("width" to width.toDouble(), "height" to height.toDouble(), "source" to source))

  private fun emitError(message: String, source: String) =
    emit("topError", mapOf("error" to message, "source" to source))

  private fun emitDisplay() = emit("topDisplay", emptyMap())

  private fun emitDisplayEnd() = emit("topDisplayEnd", emptyMap())

  private fun emit(name: String, payload: Map<String, Any>) {
    eventSink?.let {
      it(name, payload)
      return
    }
    val reactContext = context as? ReactContext ?: return
    val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(reactContext, id) ?: return
    dispatcher.dispatchEvent(TrueImageEvent(UIManagerHelper.getSurfaceId(this), id, name, payload))
  }

  private fun now(): Long = AnimationUtils.currentAnimationTimeMillis()

  private class TrueImageEvent(
    surfaceId: Int,
    viewTag: Int,
    private val name: String,
    private val payload: Map<String, Any>,
  ) : Event<TrueImageEvent>(surfaceId, viewTag) {
    override fun getEventName(): String = name

    override fun getEventData(): WritableMap = Arguments.makeNativeMap(payload)
  }
}
