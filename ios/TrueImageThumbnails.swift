import UIKit

/// Resamples a decoded image once to the size it is actually drawn at when
/// the source is more than twice as large, so a 1200 px cover in a 60 pt
/// row does not cost the GPU a full-size texture every frame.
final class TrueImageThumbnails {
  static let shared = TrueImageThumbnails()

  private let cache: NSCache<NSString, CGImage> = {
    let cache = NSCache<NSString, CGImage>()
    cache.countLimit = 64
    return cache
  }()

  private let queue = DispatchQueue(label: "TrueImage.thumbnails", qos: .userInitiated)

  func cached(key: String) -> CGImage? {
    cache.object(forKey: key as NSString)
  }

  /// Renders off the main thread and calls back on it.
  func make(
    from image: UIImage,
    pixelSize: CGSize,
    key: String,
    completion: @escaping (CGImage?) -> Void
  ) {
    if let hit = cached(key: key) {
      completion(hit)
      return
    }
    queue.async { [cache] in
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = false
      let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
      let thumb = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: pixelSize))
      }.cgImage
      if let thumb { cache.setObject(thumb, forKey: key as NSString) }
      DispatchQueue.main.async { completion(thumb) }
    }
  }
}
