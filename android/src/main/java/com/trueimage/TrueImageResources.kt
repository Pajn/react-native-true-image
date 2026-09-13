package com.trueimage

import android.content.Context
import android.graphics.drawable.Drawable
import android.util.TypedValue

object TrueImageResources {
  fun drawableId(context: Context, name: String): Int =
    context.resources.getIdentifier(name, "drawable", context.packageName)

  /**
   * A scheme-less name that resolves to an XML drawable (a vector) is
   * inflated directly and drawn in the same frame. Bitmap drawables return
   * null and fall through to Glide, which decodes them like any other image.
   */
  fun vector(context: Context, source: String): Drawable? {
    if (Source.kindOf(source) != SourceKind.RESOURCE) return null
    val id = drawableId(context, source)
    if (id == 0) return null
    val value = TypedValue()
    context.resources.getValue(id, value, true)
    val file = value.string?.toString() ?: return null
    if (!file.endsWith(".xml")) return null
    return context.resources.getDrawable(id, context.theme)
  }
}
