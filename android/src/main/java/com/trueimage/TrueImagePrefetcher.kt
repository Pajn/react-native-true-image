package com.trueimage

import android.content.Context
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import com.bumptech.glide.request.FutureTarget
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

object TrueImagePrefetcher {
  data class Request(val source: String, val headers: Map<String, String>? = null)

  /**
   * Prefetch batches usually race the mount work they are meant to feed, so
   * the loop stays off the main thread: `submit()` starts each load from
   * here, `get()` waits here, and the main looper sees one post per batch.
   */
  private val executor: ExecutorService = Executors.newCachedThreadPool { runnable ->
    Thread(runnable, "true-image-prefetch").apply { isDaemon = true }
  }

  /**
   * Loads every source with the exact request the view uses. Resolves false
   * if any of them failed. The callback runs on a background thread.
   */
  fun prefetch(context: Context, requests: List<Request>, done: (Boolean) -> Unit) {
    if (requests.isEmpty()) {
      done(true)
      return
    }
    executor.execute {
      val glide = TrueImageRequests.glide(context)
      var ok = true
      val futures = ArrayList<FutureTarget<Drawable>>(requests.size)
      for (request in requests) {
        val model = TrueImageRequests.model(context, request.source, request.headers)
        if (model == null) {
          ok = false
          continue
        }
        futures += TrueImageRequests.drawable(glide, model).submit()
      }
      for (future in futures) {
        try {
          future.get()
        } catch (e: Exception) {
          ok = false
        }
      }
      // Clearing the targets is what moves the bitmaps from Glide's active
      // set into the memory cache. One main-thread item for the whole batch.
      Handler(Looper.getMainLooper()).post { for (future in futures) glide.clear(future) }
      done(ok)
    }
  }
}
