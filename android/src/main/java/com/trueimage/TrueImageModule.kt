package com.trueimage

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableType

class TrueImageModule(reactContext: ReactApplicationContext) : NativeTrueImageSpec(reactContext) {
  override fun prefetch(urls: ReadableArray, promise: Promise) {
    val sources = (0 until urls.size()).mapNotNull { index ->
      if (urls.getType(index) == ReadableType.String) urls.getString(index) else null
    }
    TrueImagePrefetcher.prefetch(reactApplicationContext, sources) { ok -> promise.resolve(ok) }
  }

  companion object {
    const val NAME = NativeTrueImageSpec.NAME
  }
}
