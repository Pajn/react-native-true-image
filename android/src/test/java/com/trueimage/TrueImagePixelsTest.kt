package com.trueimage

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.concurrent.atomic.AtomicReference

/** The byte layout JS reads (row-major RGBA, 8-bit, not premultiplied) and the shared cache. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TrueImagePixelsTest : GlideTestCase() {
  override val useDiskCache = true

  private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

  @Test
  fun convertsArgbToRgbaInRowMajorOrder() {
    val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
    bitmap.setPixel(0, 0, Color.rgb(255, 0, 0))
    bitmap.setPixel(1, 0, Color.rgb(0, 255, 0))
    bitmap.setPixel(0, 1, Color.rgb(0, 0, 255))
    bitmap.setPixel(1, 1, Color.argb(0, 0, 0, 0))
    assertArrayEquals(
      bytes(255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0),
      TrueImagePixels.rgba(bitmap),
    )
  }

  @Test
  fun reportsTranslucentColoursUnpremultiplied() {
    val bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    bitmap.setPixel(0, 0, Color.argb(128, 200, 100, 50))
    val rgba = TrueImagePixels.rgba(bitmap).map { it.toInt() and 0xff }
    assertEquals(128, rgba[3])
    // Premultiplied storage loses a little precision; it must not halve the colour.
    for ((actual, expected) in rgba.take(3).zip(listOf(200, 100, 50))) {
      assertTrue("$actual vs $expected", kotlin.math.abs(actual - expected) <= 2)
    }
  }

  @Test
  fun drawsADrawableOverTheWholeSquare() {
    val rgba = TrueImagePixels.rgba(ColorDrawable(Color.rgb(30, 90, 200)), 4)
    assertEquals(4 * 4 * 4, rgba.size)
    for (i in rgba.indices step 4) {
      assertEquals(listOf(30, 90, 200, 255), (0 until 4).map { rgba[i + it].toInt() and 0xff })
    }
  }

  @Test
  fun samplingAPrefetchedUrlDecodesFromTheSharedDiskCache() {
    val url = "https://cdn.example.com/cover.jpg"
    assertTrue(prefetch(url))
    val result = AtomicReference<Result<String?>?>(null)
    TrueImagePixels.load(app, url, null, 16) { result.set(Result.success(it)) }
    settle { result.get() != null }
    val encoded = result.get()!!.getOrNull()
    assertNotNull(encoded)
    assertEquals(16 * 16 * 4, android.util.Base64.decode(encoded, android.util.Base64.NO_WRAP).size)
    assertEquals(1, network.fetches[url])
  }
}
