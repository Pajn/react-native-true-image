package com.trueimage

import android.net.Uri
import com.bumptech.glide.load.model.GlideUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27])
class TrueImageResourcesTest {
  private val app = RuntimeEnvironment.getApplication()

  @Test
  fun bareNameOfXmlDrawableIsInflated() {
    assertNotNull(TrueImageResources.vector(app, "true_image_test_vector"))
  }

  @Test
  fun bareNameOfBitmapFallsThroughToGlide() {
    assertNull(TrueImageResources.vector(app, "true_image_test_bitmap"))
    assertTrue(TrueImageResources.drawableId(app, "true_image_test_bitmap") != 0)
  }

  @Test
  fun schemedSourceIsNotAResource() {
    assertNull(TrueImageResources.vector(app, "https://example.com/true_image_test_vector"))
  }

  @Test
  fun unknownNameIsNull() {
    assertNull(TrueImageResources.vector(app, "no_such_drawable"))
    assertEquals(0, TrueImageResources.drawableId(app, "no_such_drawable"))
  }

  @Test
  fun modelSelection() {
    val remote = TrueImageRequests.model(app, "https://cdn.example.com/a.jpg")
    assertTrue(remote is GlideUrl)
    assertEquals("https://cdn.example.com/a.jpg", (remote as GlideUrl).toStringUrl())

    val resource = TrueImageRequests.model(app, "true_image_test_bitmap")
    assertEquals(TrueImageResources.drawableId(app, "true_image_test_bitmap"), resource)

    assertNull(TrueImageRequests.model(app, "no_such_drawable"))

    val file = TrueImageRequests.model(app, "file:///data/cache/a.jpg")
    assertTrue(file is Uri)
    assertEquals("file", (file as Uri).scheme)
  }
}
