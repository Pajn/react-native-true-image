import CoreGraphics
import Foundation

/// Pure geometry and policy shared by the view, the thumbnail tier and the
/// unit tests. Nothing here touches UIKit so it can run on any Swift host.
@objc public enum TrueImageFitMode: Int {
  case cover
  case contain
  case stretch
  case center
}

public enum TrueImagePolicy {
  /// The rect an image of `intrinsic` size occupies inside `bounds`.
  /// `cover` overflows, `contain` insets, both are centred. `stretch` fills
  /// the bounds, `center` draws at intrinsic size. A degenerate intrinsic
  /// size falls back to the full bounds.
  public static func fitRect(
    bounds: CGRect,
    intrinsic: CGSize,
    mode: TrueImageFitMode
  ) -> CGRect {
    guard intrinsic.width > 0, intrinsic.height > 0,
      bounds.width > 0, bounds.height > 0
    else { return bounds }

    let size: CGSize
    switch mode {
    case .stretch:
      return bounds
    case .center:
      size = intrinsic
    case .cover, .contain:
      let sx = bounds.width / intrinsic.width
      let sy = bounds.height / intrinsic.height
      let scale = mode == .cover ? max(sx, sy) : min(sx, sy)
      size = CGSize(width: intrinsic.width * scale, height: intrinsic.height * scale)
    }
    return CGRect(
      x: bounds.midX - size.width / 2,
      y: bounds.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  /// Pixel size to resample a decoded image to when it is drawn far below
  /// its own size. Returns nil when no thumbnail is worth making: the view
  /// has no size, the mode does not scale, or the image is under twice the
  /// drawn size on either axis.
  public static func thumbnailPixelSize(
    imagePixels: CGSize,
    drawnPoints: CGSize,
    scale: CGFloat,
    mode: TrueImageFitMode
  ) -> CGSize? {
    guard drawnPoints.width > 0, drawnPoints.height > 0, scale > 0,
      imagePixels.width > 0, imagePixels.height > 0,
      mode != .center
    else { return nil }

    let drawnPixels = CGRect(
      origin: .zero,
      size: CGSize(width: drawnPoints.width * scale, height: drawnPoints.height * scale)
    )
    let target = fitRect(bounds: drawnPixels, intrinsic: imagePixels, mode: mode).size
    guard imagePixels.width >= target.width * 2, imagePixels.height >= target.height * 2
    else { return nil }
    return CGSize(width: ceil(target.width), height: ceil(target.height))
  }

  /// Memory cache ceiling: a sixteenth of physical memory, capped at 256 MB.
  /// Set because low-memory devices running long sessions were being
  /// terminated under the library default.
  public static func memoryCacheCost(physicalMemory: UInt64) -> UInt {
    let cap: UInt64 = 256 * 1024 * 1024
    return UInt(min(physicalMemory / 16, cap))
  }

  /// A fade softens an image arriving late; a cached image in an empty view
  /// is not late and draws at once. Replacing a displayed image always
  /// crossfades when a transition is set. Native resources never fade.
  public static func shouldFade(
    transitionMs: Int,
    fromMemory: Bool,
    hasContents: Bool,
    isResource: Bool
  ) -> Bool {
    guard transitionMs > 0, !isResource else { return false }
    return !(fromMemory && !hasContents)
  }

  public enum FadeKeyPath: String {
    case opacity
    case contents
  }

  /// An empty layer fades its opacity in; a layer that already shows an
  /// image crossfades its contents so nothing double-composites.
  public static func fadeKeyPath(hasContents: Bool) -> FadeKeyPath {
    hasContents ? .contents : .opacity
  }

  public static func fadeDuration(transitionMs: Int) -> TimeInterval {
    TimeInterval(transitionMs) / 1000
  }

  /// Turns a scheme-less name into nil so the caller takes the native
  /// resource branch; accepts `file://` paths containing spaces.
  public static func url(from source: String) -> URL? {
    guard let components = URLComponents(string: source), components.scheme != nil else {
      // URLComponents rejects unescaped spaces; retry with them encoded so a
      // `file:///…/My Cover.png` still parses. Anything without a scheme is a
      // resource name.
      let escaped = source.replacingOccurrences(of: " ", with: "%20")
      guard escaped != source,
        let retry = URLComponents(string: escaped), retry.scheme != nil
      else { return nil }
      return retry.url
    }
    return components.url
  }

  /// Cache key for a resampled thumbnail. Varies with the source, the blur
  /// and the target size so a resize or a blur change never reuses a stale one.
  public static func thumbnailKey(source: String, blurRadius: CGFloat, pixelSize: CGSize) -> String {
    "\(source)|b\(blurRadius)|\(Int(pixelSize.width))x\(Int(pixelSize.height))"
  }
}
