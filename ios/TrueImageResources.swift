import UIKit

/// Scheme-less sources name an asset catalog image. They are rasterised at
/// the view's size on the main thread, tinted, and drawn in the same frame.
enum TrueImageResources {
  struct Raster {
    let image: CGImage
    /// Intrinsic size of the catalog image in pixels, reported through onLoad.
    let pixelSize: CGSize
  }

  static func image(named name: String, traits: UITraitCollection) -> UIImage? {
    UIImage(named: name, in: .main, compatibleWith: traits)
  }

  static func raster(
    _ image: UIImage,
    size: CGSize,
    scale: CGFloat,
    tint: UIColor?,
    mode: TrueImageFitMode,
    traits: UITraitCollection
  ) -> Raster? {
    guard size.width > 0, size.height > 0 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let rect = TrueImagePolicy.fitRect(
      bounds: CGRect(origin: .zero, size: size),
      intrinsic: image.size,
      mode: mode
    )
    // Resolve dynamic colours against the current traits so a
    // DynamicColorIOS tint re-rasterises correctly on appearance changes.
    let resolvedTint = tint?.resolvedColor(with: traits)
    let drawn = resolvedTint.map { image.withTintColor($0, renderingMode: .alwaysOriginal) } ?? image
    guard let cg = renderer.image({ _ in drawn.draw(in: rect) }).cgImage else { return nil }
    return Raster(
      image: cg,
      pixelSize: CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    )
  }
}
