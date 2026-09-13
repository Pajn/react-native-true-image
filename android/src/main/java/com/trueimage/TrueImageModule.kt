package com.trueimage

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableType

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
      parsed += TrueImagePrefetcher.Request(uri, headers)
    }
    TrueImagePrefetcher.prefetch(reactApplicationContext, parsed) { ok -> promise.resolve(ok && allValid) }
  }

  companion object {
    const val NAME = NativeTrueImageSpec.NAME
  }
}
