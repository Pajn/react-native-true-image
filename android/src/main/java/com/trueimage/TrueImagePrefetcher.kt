package com.trueimage

import android.content.Context
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.target.Target
import com.bumptech.glide.request.transition.Transition

object TrueImagePrefetcher {
  /**
   * Loads every source with the exact request the view uses. Resolves false
   * if any of them failed. Runs on the main looper because Glide requires it;
   * the callback fires there too.
   */
  fun prefetch(context: Context, sources: List<String>, done: (Boolean) -> Unit) {
    if (sources.isEmpty()) {
      done(true)
      return
    }
    val main = Handler(Looper.getMainLooper())
    main.post {
      val glide = TrueImageRequests.glide(context)
      var remaining = sources.size
      var ok = true

      fun finish(success: Boolean, target: Target<Drawable>?) {
        if (!success) ok = false
        // Clearing the target is what moves the bitmap from Glide's active
        // set into the memory cache. Post it so it never runs inside the
        // callback that delivered it.
        if (target != null) main.post { glide.clear(target) }
        if (--remaining == 0) done(ok)
      }

      for (source in sources) {
        val model = TrueImageRequests.model(context, source)
        if (model == null) {
          finish(false, null)
          continue
        }
        val target = object : CustomTarget<Drawable>() {
          override fun onResourceReady(resource: Drawable, transition: Transition<in Drawable>?) =
            finish(true, this)

          override fun onLoadFailed(errorDrawable: Drawable?) = finish(false, this)

          override fun onLoadCleared(placeholder: Drawable?) = Unit
        }
        TrueImageRequests.drawable(glide, model).into(target)
      }
    }
  }
}
