package com.trueimage

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableType
import kotlin.math.roundToInt

class TrueImageModule(reactContext: ReactApplicationContext) : NativeTrueImageSpec(reactContext) {
  override fun prefetch(requests: ReadableArray, promise: Promise) {
    var allValid = true
    val parsed = ArrayList<TrueImagePrefetcher.Request>(requests.size())
    for (i in 0 until requests.size()) {
      val map = if (requests.getType(i) == ReadableType.Map) requests.getMap(i) else null
      val uri = map?.getString("uri")
      if (uri == null) {
        allValid = false
        continue
      }
      val headers = if (map.hasKey("headers")) TrueImageHeaders.fromArray(map.getArray("headers")) else null
      val density = reactApplicationContext.resources.displayMetrics.density
      fun number(key: String, fallback: Double) = if (map.hasKey(key) && !map.isNull(key)) map.getDouble(key) else fallback
      val w = number("displayWidth", 0.0)
      val h = number("displayHeight", 0.0)
      val threshold = number("downsampleThreshold", 2.0)
      if (!w.isFinite() || !h.isFinite() || w < 0 || h < 0 || (w > 0) != (h > 0) ||
          !threshold.isFinite() || (threshold != 0.0 && threshold < 1.0)) {
        allValid = false
        continue
      }
      val mode = FitMode.from(if (map.hasKey("resizeMode")) map.getString("resizeMode") else null)
      val size = TrueImageRequests.Size((w * density).roundToInt(), (h * density).roundToInt(), mode, threshold.toFloat())
      parsed += TrueImagePrefetcher.Request(uri, headers, size)
    }
    TrueImagePrefetcher.prefetch(reactApplicationContext, parsed) { ok -> promise.resolve(ok && allValid) }
  }

  companion object {
    const val NAME = NativeTrueImageSpec.NAME
  }
}
