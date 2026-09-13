package com.trueimage

import android.view.View
import com.facebook.react.bridge.ColorPropConverter
import com.facebook.react.bridge.DynamicFromObject
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.BackgroundStyleApplicator
import com.facebook.react.uimanager.LengthPercentage
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.ViewProps
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.uimanager.style.BorderRadiusProp
import com.facebook.react.uimanager.style.BorderStyle
import com.facebook.react.uimanager.style.LogicalEdge
import com.facebook.react.viewmanagers.TrueImageViewManagerDelegate
import com.facebook.react.viewmanagers.TrueImageViewManagerInterface

@ReactModule(name = TrueImageViewManager.NAME)
class TrueImageViewManager :
  SimpleViewManager<TrueImageView>(),
  TrueImageViewManagerInterface<TrueImageView> {
  private val delegate: ViewManagerDelegate<TrueImageView> = BorderAwareDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<TrueImageView> = delegate

  override fun getName(): String = NAME

  override fun createViewInstance(context: ThemedReactContext): TrueImageView = TrueImageView(context)

  @ReactProp(name = "source")
  override fun setSource(view: TrueImageView, value: String?) {
    view.source = value
  }

  @ReactProp(name = "headers")
  override fun setHeaders(view: TrueImageView, value: ReadableArray?) {
    view.headers = TrueImageHeaders.fromArray(value)
  }

  @ReactProp(name = "resizeMode")
  override fun setResizeMode(view: TrueImageView, value: String?) {
    view.fitMode = FitMode.from(value)
  }

  @ReactProp(name = "transition")
  override fun setTransition(view: TrueImageView, value: Int) {
    view.transitionMs = value
  }

  @ReactProp(name = "blurRadius")
  override fun setBlurRadius(view: TrueImageView, value: Float) {
    view.blurRadius = value
  }

  @ReactProp(name = "tintColor", customType = "Color")
  override fun setTintColor(view: TrueImageView, value: Int?) {
    view.tintColor = value
  }

  @ReactProp(name = "recyclingKey")
  override fun setRecyclingKey(view: TrueImageView, value: String?) {
    view.recyclingKey = value
  }

  /** All props for one update have been set; apply them together. */
  override fun onAfterUpdateTransaction(view: TrueImageView) {
    super.onAfterUpdateTransaction(view)
    view.commit()
  }

  override fun onDropViewInstance(view: TrueImageView) {
    super.onDropViewInstance(view)
    view.release()
  }

  override fun getExportedCustomDirectEventTypeConstants(): MutableMap<String, Any> {
    val events = super.getExportedCustomDirectEventTypeConstants() ?: mutableMapOf()
    events["topLoad"] = mapOf("registrationName" to "onLoad")
    events["topError"] = mapOf("registrationName" to "onError")
    events["topDisplay"] = mapOf("registrationName" to "onDisplay")
    events["topDisplayEnd"] = mapOf("registrationName" to "onDisplayEnd")
    return events
  }

  /**
   * The generated delegate hands border props to base setters that only log
   * a warning. Route them to the style applicator instead, so the border box
   * draws and `onDraw` clips the image to it, and no consumer needs a
   * wrapper view for rounded corners.
   */
  private class BorderAwareDelegate(manager: TrueImageViewManager) : ViewManagerDelegate<TrueImageView> {
    private val generated = TrueImageViewManagerDelegate<TrueImageView, TrueImageViewManager>(manager)

    override fun receiveCommand(view: TrueImageView, commandName: String, args: ReadableArray) =
      generated.receiveCommand(view, commandName, args)

    override fun setProperty(view: TrueImageView, propName: String, value: Any?) {
      RADII[propName]?.let { corner ->
        BackgroundStyleApplicator.setBorderRadius(
          view, corner, LengthPercentage.setFromDynamic(DynamicFromObject(value)),
        )
        view.invalidate()
        return
      }
      WIDTHS[propName]?.let { edge ->
        BackgroundStyleApplicator.setBorderWidth(view, edge, (value as? Double)?.toFloat())
        view.invalidate()
        return
      }
      COLORS[propName]?.let { edge ->
        val color = if (value == null) null else ColorPropConverter.getColor(value, view.context)
        BackgroundStyleApplicator.setBorderColor(view, edge, color)
        view.invalidate()
        return
      }
      if (propName == "borderStyle") {
        BackgroundStyleApplicator.setBorderStyle(view, (value as? String)?.let { BorderStyle.fromString(it) })
        view.invalidate()
        return
      }
      generated.setProperty(view, propName, value)
    }
  }

  companion object {
    const val NAME = "TrueImageView"

    private val RADII: Map<String, BorderRadiusProp> = mapOf(
      ViewProps.BORDER_RADIUS to BorderRadiusProp.BORDER_RADIUS,
      ViewProps.BORDER_TOP_LEFT_RADIUS to BorderRadiusProp.BORDER_TOP_LEFT_RADIUS,
      ViewProps.BORDER_TOP_RIGHT_RADIUS to BorderRadiusProp.BORDER_TOP_RIGHT_RADIUS,
      ViewProps.BORDER_BOTTOM_RIGHT_RADIUS to BorderRadiusProp.BORDER_BOTTOM_RIGHT_RADIUS,
      ViewProps.BORDER_BOTTOM_LEFT_RADIUS to BorderRadiusProp.BORDER_BOTTOM_LEFT_RADIUS,
      ViewProps.BORDER_TOP_START_RADIUS to BorderRadiusProp.BORDER_TOP_START_RADIUS,
      ViewProps.BORDER_TOP_END_RADIUS to BorderRadiusProp.BORDER_TOP_END_RADIUS,
      ViewProps.BORDER_BOTTOM_START_RADIUS to BorderRadiusProp.BORDER_BOTTOM_START_RADIUS,
      ViewProps.BORDER_BOTTOM_END_RADIUS to BorderRadiusProp.BORDER_BOTTOM_END_RADIUS,
      ViewProps.BORDER_END_END_RADIUS to BorderRadiusProp.BORDER_END_END_RADIUS,
      ViewProps.BORDER_END_START_RADIUS to BorderRadiusProp.BORDER_END_START_RADIUS,
      ViewProps.BORDER_START_END_RADIUS to BorderRadiusProp.BORDER_START_END_RADIUS,
      ViewProps.BORDER_START_START_RADIUS to BorderRadiusProp.BORDER_START_START_RADIUS,
    )

    private val WIDTHS: Map<String, LogicalEdge> = mapOf(
      ViewProps.BORDER_WIDTH to LogicalEdge.ALL,
      ViewProps.BORDER_LEFT_WIDTH to LogicalEdge.LEFT,
      ViewProps.BORDER_RIGHT_WIDTH to LogicalEdge.RIGHT,
      ViewProps.BORDER_TOP_WIDTH to LogicalEdge.TOP,
      ViewProps.BORDER_BOTTOM_WIDTH to LogicalEdge.BOTTOM,
      ViewProps.BORDER_START_WIDTH to LogicalEdge.START,
      ViewProps.BORDER_END_WIDTH to LogicalEdge.END,
    )

    private val COLORS: Map<String, LogicalEdge> = mapOf(
      ViewProps.BORDER_COLOR to LogicalEdge.ALL,
      ViewProps.BORDER_LEFT_COLOR to LogicalEdge.LEFT,
      ViewProps.BORDER_RIGHT_COLOR to LogicalEdge.RIGHT,
      ViewProps.BORDER_TOP_COLOR to LogicalEdge.TOP,
      ViewProps.BORDER_BOTTOM_COLOR to LogicalEdge.BOTTOM,
      ViewProps.BORDER_START_COLOR to LogicalEdge.START,
      ViewProps.BORDER_END_COLOR to LogicalEdge.END,
      ViewProps.BORDER_BLOCK_COLOR to LogicalEdge.BLOCK,
      ViewProps.BORDER_BLOCK_END_COLOR to LogicalEdge.BLOCK_END,
      ViewProps.BORDER_BLOCK_START_COLOR to LogicalEdge.BLOCK_START,
    )
  }
}
