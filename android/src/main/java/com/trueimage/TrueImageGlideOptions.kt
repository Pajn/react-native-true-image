package com.trueimage

import com.bumptech.glide.GlideBuilder
import com.bumptech.glide.load.engine.executor.GlideExecutor

/**
 * Glide decodes disk-cached images on a single thread by default: a
 * `DecodeJob` starts on the disk cache executor and only moves to the
 * multi-threaded source executor when it has to fetch. A cold scroll through
 * a list whose covers are already on disk therefore decodes them one at a
 * time.
 *
 * Executors can only be set through [GlideBuilder], which belongs to the
 * app's `AppGlideModule`; a library must not ship one. Apps that want
 * parallel disk-cache decoding call [apply] from `applyOptions`.
 */
object TrueImageGlideOptions {
  /** Same sizing Glide uses for its source executor: min(4, CPU cores). */
  fun decodeThreadCount(): Int = GlideExecutor.calculateBestThreadCount()

  fun apply(builder: GlideBuilder, threadCount: Int = decodeThreadCount()): GlideBuilder =
    builder.setDiskCacheExecutor(
      GlideExecutor.newDiskCacheBuilder()
        .setThreadCount(threadCount)
        .setName("true-image-disk-cache")
        .build(),
    )
}
