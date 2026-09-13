import Foundation

/// Parses sources with the same rules the view uses, then hands the URLs to
/// the loader. Resolves false if any URL failed to load or to parse.
@objc public final class TrueImagePrefetch: NSObject {
  @objc public static func prefetch(_ sources: [String], completion: @escaping (Bool) -> Void) {
    TrueImageConfiguration.configureOnce()
    let urls = sources.compactMap(TrueImagePolicy.url(from:))
    let allValid = urls.count == sources.count
    TrueImageLoader.prefetchURLs(urls) { ok in completion(ok && allValid) }
  }
}

enum TrueImageConfiguration {
  private static let configured: Void = TrueImageLoader.configureOnce(
    withMaxMemoryCost: TrueImagePolicy.memoryCacheCost(
      physicalMemory: ProcessInfo.processInfo.physicalMemory
    )
  )

  static func configureOnce() {
    _ = configured
  }
}
