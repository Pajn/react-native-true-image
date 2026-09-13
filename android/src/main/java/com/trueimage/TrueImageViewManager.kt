package com.trueimage

import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.TrueImageViewManagerDelegate
import com.facebook.react.viewmanagers.TrueImageViewManagerInterface

@ReactModule(name = TrueImageViewManager.NAME)
class TrueImageViewManager :
  SimpleViewManager<TrueImageView>(),
  TrueImageViewManagerInterface<TrueImageView> {
  private val delegate: ViewManagerDelegate<TrueImageView> = TrueImageViewManagerDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<TrueImageView> = delegate

  override fun getName(): String = NAME

  override fun createViewInstance(context: ThemedReactContext): TrueImageView = TrueImageView(context)

  @ReactProp(name = "source")
  override fun setSource(view: TrueImageView, value: String?) {
    view.source = value
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

  companion object {
    const val NAME = "TrueImageView"
  }
}
