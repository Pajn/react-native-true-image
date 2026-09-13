package com.trueimage

import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableType

object TrueImageHeaders {
  /** Parses the `[{ name, value }]` list JS sends; null when there is nothing to send. */
  fun fromArray(array: ReadableArray?): Map<String, String>? {
    if (array == null || array.size() == 0) return null
    val headers = LinkedHashMap<String, String>()
    for (i in 0 until array.size()) {
      if (array.getType(i) != ReadableType.Map) continue
      val entry = array.getMap(i) ?: continue
      val name = entry.getString("name") ?: continue
      val value = entry.getString("value") ?: continue
      headers[name] = value
    }
    return headers.ifEmpty { null }
  }
}
