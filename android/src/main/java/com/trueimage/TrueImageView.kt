package com.trueimage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PaintFlagsDrawFilter
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
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
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * One view, one canvas, one image (two during a crossfade). No child views
 * and no placeholders: that is the performance premise of the whole module.
 * Props are set by the view manager and applied together in [commit].
 */
class TrueImageView(context: Context) : View(context) {
  // MARK: Props

  var source: String? = null
  var fitMode: FitMode = FitMode.COVER
  /** Fade duration in milliseconds. */
  var transitionMs: Int = 0
  var blurRadius: Float = 0f
  var tintColor: Int? = null
  var recyclingKey: String? = null

  // MARK: State

  private data class Request(val source: String)

  /** One image and the Glide target that owns its bitmap. */
  private class Layer(val request: Request, val fromResource: Boolean) {
    var drawable: Drawable? = null
    var target: Target<Drawable>? = null
    var fromMemory = false
  }

  private var current: Layer? = null
  private var previous: Layer? = null
  private var pending: Layer? = null
  private var crossfade: Crossfade? = null
  /** True while the running crossfade is a fade-in over an empty view. */
  private var fadeFromEmpty = false
  private var appliedRecyclingKey: String? = null
  private var appliedFitMode = FitMode.COVER
  private var appliedTint: Int? = null
  private var appliedBlur = 0f
  private var blurStandIn: Pair<Layer, Drawable>? = null

  private val filter = PaintFlagsDrawFilter(0, Paint.FILTER_BITMAP_FLAG)

  /** Tests observe events here instead of through the React event dispatcher. */
  internal var eventSink: ((name: String, payload: Map<String, Any>) -> Unit)? = null

  internal val hasImage: Boolean get() = current?.drawable != null
  internal val isCrossfading: Boolean get() = crossfade != null
  internal val hasPendingLoad: Boolean get() = pending != null
  internal val hasBlurStandIn: Boolean get() = blurStandIn != null
  internal val currentDrawable: Drawable? get() = current?.drawable

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
      blurStandIn = null
      updateRenderEffect()
      invalidate()
    }
    if (tintColor != appliedTint) {
      appliedTint = tintColor
      applyTint(current)
      applyTint(previous)
      invalidate()
    }
    if (blurRadius != appliedBlur) {
      appliedBlur = blurRadius
      blurStandIn = null
      updateRenderEffect()
      invalidate()
    }

    val src = source
    if (src.isNullOrEmpty()) {
      clear()
      return
    }
    val request = Request(src)
    if (current?.request == request) {
      cancelPending()
      return
    }
    if (pending?.request == request) return
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
    blurStandIn = null
  }

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    // A recycling key may have cleared this view while it was detached.
    val src = source
    if (src != null && current == null && pending == null) load(Request(src))
  }

  override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
    super.onSizeChanged(w, h, oldw, oldh)
    blurStandIn = null
    updateRenderEffect()
  }

  // MARK: Loading

  private fun load(request: Request) {
    cancelPending()

    val vector = TrueImageResources.vector(context, request.source)
    if (vector != null) {
      val layer = Layer(request, fromResource = true)
      layer.drawable = vector.mutate()
      layer.fromMemory = true
      show(layer)
      return
    }

    val model = TrueImageRequests.model(context, request.source)
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
        pending = null
        // Two views sharing one cached drawable must not share alpha.
        layer.drawable = resource.mutate()
        show(layer)
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
  }

  private fun cancelPending() {
    val layer = pending ?: return
    pending = null
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
    blurStandIn = null
    updateRenderEffect()
    invalidate()
  }

  // MARK: Display

  private fun show(layer: Layer) {
    val drawable = layer.drawable ?: return
    val hasContent = current?.drawable != null
    val fade = transitionMs > 0 && !layer.fromResource && !(layer.fromMemory && !hasContent)
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
    blurStandIn = null
    updateRenderEffect()

    if (fade) {
      // The interrupted crossfade never completes, so it never reports
      // onDisplayEnd; this one reports in its turn.
      crossfade = Crossfade(transitionMs.toLong(), now, startAlpha)
      fadeFromEmpty = previous == null
      emitDisplay()
      postInvalidateOnAnimation()
    } else {
      crossfade = null
      drawable.alpha = 255
      emitDisplay()
      emitDisplayEnd()
      invalidate()
    }
  }

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

    previous?.drawable?.let { draw(canvas, it, 1f - alpha) }
    current?.let { layer -> layer.drawable?.let { draw(canvas, standIn(layer, it), alpha) } }

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

  private fun draw(canvas: Canvas, drawable: Drawable, alpha: Float) {
    val rect = Fit.rect(
      width.toFloat(), height.toFloat(),
      drawable.intrinsicWidth.toFloat(), drawable.intrinsicHeight.toFloat(),
      fitMode,
    )
    drawable.setBounds(
      rect.left.roundToInt(), rect.top.roundToInt(),
      rect.right.roundToInt(), rect.bottom.roundToInt(),
    )
    drawable.alpha = (alpha.coerceIn(0f, 1f) * 255f).roundToInt()
    drawable.draw(canvas)
  }

  // MARK: Blur

  private fun sigmaPx(drawable: Drawable): Float {
    val drawn = Fit.rect(
      width.toFloat(), height.toFloat(),
      drawable.intrinsicWidth.toFloat(), drawable.intrinsicHeight.toFloat(),
      fitMode,
    )
    return Blur.sigmaPx(
      blurRadius, drawn.width, drawable.intrinsicWidth.toFloat(),
      resources.displayMetrics.density,
    )
  }

  /** API 31+: blur the view itself, scaled from source pixels to view pixels. */
  private fun updateRenderEffect() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    val drawable = current?.drawable
    val sigma = if (drawable == null || width == 0) 0f else sigmaPx(drawable)
    setRenderEffect(
      if (sigma > 0f) RenderEffect.createBlurEffect(sigma, sigma, Shader.TileMode.CLAMP) else null,
    )
  }

  /**
   * Below API 31 a downscaled copy drawn back up with bitmap filtering stands
   * in for a blur. Cached per image; dropped on size and radius changes.
   */
  private fun standIn(layer: Layer, drawable: Drawable): Drawable {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S || blurRadius <= 0f) return drawable
    blurStandIn?.let { (owner, cached) -> if (owner === layer) return cached }
    val factor = Blur.standInFactor(sigmaPx(drawable))
    if (factor <= 1f || drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) return drawable
    val w = max(1, (drawable.intrinsicWidth / factor).roundToInt())
    val h = max(1, (drawable.intrinsicHeight / factor).roundToInt())
    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    drawable.setBounds(0, 0, w, h)
    drawable.alpha = 255
    drawable.draw(Canvas(bitmap))
    val result = BitmapDrawable(resources, bitmap).apply { isFilterBitmap = true }
    blurStandIn = layer to result
    return result
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
