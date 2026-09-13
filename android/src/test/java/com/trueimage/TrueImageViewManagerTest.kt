package com.trueimage

import com.facebook.react.bridge.JavaOnlyMap
import com.facebook.react.uimanager.BackgroundStyleApplicator
import com.facebook.react.uimanager.ReactStylesDiffMap
import com.facebook.react.uimanager.style.BorderRadiusProp
import com.facebook.react.uimanager.style.LogicalEdge
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Border props reach the style applicator, so rounded corners need no wrapper view. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
class TrueImageViewManagerTest {
  private val app = RuntimeEnvironment.getApplication()
  private val manager = TrueImageViewManager()

  @Before
  fun initDisplayMetrics() {
    com.facebook.react.uimanager.DisplayMetricsHolder.initDisplayMetricsIfNotInitialized(app)
  }

  private fun update(view: TrueImageView, vararg pairs: Any) {
    manager.updateProperties(view, ReactStylesDiffMap(JavaOnlyMap.of(*pairs)))
  }

  @Test
  fun borderRadiusIsApplied() {
    val view = TrueImageView(app)
    update(view, "borderRadius", 8.0, "borderTopLeftRadius", 2.0)
    val all = BackgroundStyleApplicator.getBorderRadius(view, BorderRadiusProp.BORDER_RADIUS)
    val topLeft = BackgroundStyleApplicator.getBorderRadius(view, BorderRadiusProp.BORDER_TOP_LEFT_RADIUS)
    assertNotNull(all)
    assertEquals(8f, all!!.resolve(100f), 0f)
    assertEquals(2f, topLeft!!.resolve(100f), 0f)
  }

  @Test
  fun borderWidthColorAndStyleAreApplied() {
    val view = TrueImageView(app)
    update(view, "borderWidth", 2.0, "borderColor", -65536.0, "borderStyle", "dashed", "borderLeftWidth", 4.0)
    assertEquals(2f, BackgroundStyleApplicator.getBorderWidth(view, LogicalEdge.ALL))
    assertEquals(4f, BackgroundStyleApplicator.getBorderWidth(view, LogicalEdge.LEFT))
    assertEquals(-65536, BackgroundStyleApplicator.getBorderColor(view, LogicalEdge.ALL))
  }

  @Test
  fun ownPropsStillReachTheView() {
    val view = TrueImageView(app)
    update(view, "resizeMode", "contain", "transition", 250, "recyclingKey", "row-1")
    assertEquals(FitMode.CONTAIN, view.fitMode)
    assertEquals(250, view.transitionMs)
    assertEquals("row-1", view.recyclingKey)
  }

  @Test
  fun headersPropIsParsed() {
    val view = TrueImageView(app)
    val headers = com.facebook.react.bridge.JavaOnlyArray.of(
      JavaOnlyMap.of("name", "Authorization", "value", "Bearer t"),
      JavaOnlyMap.of("name", "X-Proxy", "value", "shelf"),
    )
    update(view, "headers", headers)
    assertEquals(mapOf("Authorization" to "Bearer t", "X-Proxy" to "shelf"), view.headers)
    manager.updateProperties(view, ReactStylesDiffMap(JavaOnlyMap().apply { putNull("headers") }))
    assertEquals(null, view.headers)
  }
}
