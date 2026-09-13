import QuartzCore
import UIKit

/// One view, one layer, one image. No subviews and no placeholder views:
/// that is the performance premise of the whole module. Props are set by
/// the Fabric component view and applied together in `commit()`.
@objc public final class TrueImageView: UIView {
  // MARK: Props

  @objc public var source: String?
  @objc public var fitMode: TrueImageFitMode = .cover
  /// Fade duration in milliseconds.
  @objc public var transition: Int = 0
  @objc public var blurRadius: CGFloat = 0
  @objc public var tint: UIColor?
  @objc public var recyclingKey: String?

  // MARK: Events

  /// (pixel width, pixel height, source)
  @objc public var onLoad: ((CGFloat, CGFloat, String) -> Void)?
  /// (message, source)
  @objc public var onError: ((String, String) -> Void)?
  @objc public var onDisplay: (() -> Void)?
  @objc public var onDisplayEnd: (() -> Void)?

  // MARK: State

  private struct Request: Equatable {
    let source: String
    let blurRadius: CGFloat
  }

  private enum Kind {
    case bitmap(UIImage)
    case resource(UIImage)
  }

  private struct Loaded {
    let request: Request
    let kind: Kind
  }

  private static let fadeKey = "fade"

  private let imageLayer = CALayer()
  private var loaded: Loaded?
  private var pending: (request: Request, token: Any?)?
  /// Bumped whenever an in-flight load is abandoned; stale completions compare against it.
  private var generation = 0
  /// Identifies the fade that is allowed to report onDisplayEnd.
  private var fadeToken = 0
  private var reportedRequest: Request?
  private var thumbnailKey: String?
  private var rasterSize: CGSize = .zero
  private var appliedRecyclingKey: String?
  private var appliedFitMode: TrueImageFitMode = .cover
  private var appliedTint: UIColor?

  // MARK: Lifecycle

  public override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    imageLayer.masksToBounds = true
    imageLayer.contentsScale = displayScale
    // Setting contents, opacity or geometry must never install an implicit
    // animation under the fade; every fade is added explicitly.
    imageLayer.actions = [
      "contents": NSNull(),
      "opacity": NSNull(),
      "bounds": NSNull(),
      "position": NSNull(),
      "contentsGravity": NSNull(),
    ]
    layer.addSublayer(imageLayer)
    applyGravity()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  deinit {
    TrueImageLoader.cancel(pending?.token)
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    imageLayer.frame = bounds
    imageLayer.contentsScale = displayScale
    guard let loaded else { return }
    switch loaded.kind {
    case .resource(let image):
      if bounds.size != rasterSize { rasterise(image, loaded.request) }
    case .bitmap(let image):
      refineContents(image, loaded.request)
    }
  }

  public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    // Dynamic tints resolve differently per appearance; re-rasterise.
    if let loaded, case .resource(let image) = loaded.kind {
      rasterise(image, loaded.request)
    }
  }

  private var displayScale: CGFloat {
    let scale = traitCollection.displayScale
    return scale > 0 ? scale : UIScreen.main.scale
  }

  // MARK: Fabric entry points

  /// Applies every prop set since the last commit. Runs inside the mount
  /// transaction, so a recycling key change clears the layer before the new
  /// source loads and the two never crossfade into each other.
  @objc public func commit() {
    if recyclingKey != appliedRecyclingKey {
      appliedRecyclingKey = recyclingKey
      clear()
    }
    if fitMode != appliedFitMode {
      appliedFitMode = fitMode
      if let loaded {
        switch loaded.kind {
        case .resource(let image): rasterise(image, loaded.request)
        case .bitmap(let image):
          applyGravity()
          thumbnailKey = nil
          refineContents(image, loaded.request)
        }
      } else {
        applyGravity()
      }
    }
    if tint != appliedTint {
      appliedTint = tint
      if let loaded, case .resource(let image) = loaded.kind {
        rasterise(image, loaded.request)
      }
    }

    guard let source, !source.isEmpty else {
      clear()
      return
    }
    let request = Request(source: source, blurRadius: blurRadius)
    if loaded?.request == request {
      cancelPending()
      return
    }
    if pending?.request == request { return }
    load(request)
  }

  /// Fabric reuses component views for unrelated components.
  @objc public func prepareForRecycle() {
    clear()
    source = nil
    recyclingKey = nil
    appliedRecyclingKey = nil
    transition = 0
    blurRadius = 0
    tint = nil
    appliedTint = nil
    fitMode = .cover
    appliedFitMode = .cover
    onLoad = nil
    onError = nil
    onDisplay = nil
    onDisplayEnd = nil
    applyGravity()
  }

  // MARK: Loading

  private func load(_ request: Request) {
    cancelPending()
    let gen = generation

    guard let url = TrueImagePolicy.url(from: request.source) else {
      loadResource(request)
      return
    }

    TrueImageConfiguration.configureOnce()
    let token = TrueImageLoader.load(url, blurRadius: request.blurRadius) {
      [weak self] image, fromMemory, error in
      // A load superseded by a newer source is silent: no onError, no image.
      guard let self, self.generation == gen else { return }
      self.pending = nil
      if let image {
        self.show(image, request: request, fromMemory: fromMemory)
      } else {
        self.onError?(error ?? "Failed to load image", request.source)
      }
    }
    // A memory hit completes synchronously inside load(); only track
    // operations that are still in flight.
    if generation == gen, loaded?.request != request {
      pending = (request, token)
    }
  }

  /// Scheme-less sources: inflated and drawn in the same frame, never faded.
  private func loadResource(_ request: Request) {
    guard let image = TrueImageResources.image(named: request.source, traits: traitCollection) else {
      clear()
      onError?("No image named \"\(request.source)\" in the asset catalog", request.source)
      return
    }
    interruptFade()
    loaded = Loaded(request: request, kind: .resource(image))
    thumbnailKey = nil
    rasterSize = .zero
    rasterise(image, request)
  }

  private func cancelPending() {
    TrueImageLoader.cancel(pending?.token)
    pending = nil
    generation += 1
  }

  private func clear() {
    cancelPending()
    interruptFade()
    imageLayer.contents = nil
    imageLayer.opacity = 1
    loaded = nil
    reportedRequest = nil
    thumbnailKey = nil
    rasterSize = .zero
  }

  // MARK: Display

  private func show(_ image: UIImage, request: Request, fromMemory: Bool) {
    // Read the model layer, not the presentation layer: a clear followed by
    // a new image inside one transaction must count as an empty layer.
    let hasContents = imageLayer.contents != nil
    let fade = TrueImagePolicy.shouldFade(
      transitionMs: transition,
      fromMemory: fromMemory,
      hasContents: hasContents,
      isResource: false
    )
    loaded = Loaded(request: request, kind: .bitmap(image))
    reportedRequest = request
    thumbnailKey = nil
    let contents = image.cgImage
    applyGravity()

    onLoad?(image.size.width * image.scale, image.size.height * image.scale, request.source)

    if fade {
      runFade(to: contents, hasContents: hasContents)
      onDisplay?()
    } else {
      interruptFade()
      imageLayer.contents = contents
      imageLayer.opacity = 1
      onDisplay?()
      onDisplayEnd?()
    }
    refineContents(image, request)
  }

  /// Removes a running fade. Its delegate sees `finished == false` and stays
  /// silent; the image that replaced it reports onDisplayEnd in its turn.
  private func interruptFade() {
    fadeToken += 1
    imageLayer.removeAnimation(forKey: Self.fadeKey)
  }

  private func runFade(to contents: CGImage?, hasContents: Bool) {
    let running = imageLayer.animation(forKey: Self.fadeKey) as? CABasicAnimation
    let resumingOpacity = running?.keyPath == TrueImagePolicy.FadeKeyPath.opacity.rawValue
    let keyPath: TrueImagePolicy.FadeKeyPath =
      resumingOpacity ? .opacity : TrueImagePolicy.fadeKeyPath(hasContents: hasContents)

    let animation = CABasicAnimation(keyPath: keyPath.rawValue)
    switch keyPath {
    case .opacity:
      // resumedFade: an image part-way in carries on from where it was.
      let from = resumingOpacity ? (imageLayer.presentation()?.opacity ?? 0) : 0
      animation.fromValue = from
      animation.toValue = 1
      imageLayer.contents = contents
      imageLayer.opacity = 1
    case .contents:
      animation.fromValue = imageLayer.contents
      animation.toValue = contents
      imageLayer.contents = contents
    }
    animation.duration = TrueImagePolicy.fadeDuration(transitionMs: transition)

    fadeToken += 1
    let token = fadeToken
    animation.delegate = FadeDelegate { [weak self] finished in
      guard let self, finished, self.fadeToken == token else { return }
      self.onDisplayEnd?()
    }
    // Adding under the same key replaces any running fade.
    imageLayer.add(animation, forKey: Self.fadeKey)
  }

  private func applyGravity() {
    switch fitMode {
    case .cover: imageLayer.contentsGravity = .resizeAspectFill
    case .contain: imageLayer.contentsGravity = .resizeAspect
    case .stretch: imageLayer.contentsGravity = .resize
    case .center: imageLayer.contentsGravity = .center
    }
  }

  /// Swaps in a thumbnail resampled to the drawn size when the image is far
  /// larger than the view. Never fades; skips when the key is unchanged.
  private func refineContents(_ image: UIImage, _ request: Request) {
    let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    guard
      let size = TrueImagePolicy.thumbnailPixelSize(
        imagePixels: pixels,
        drawnPoints: bounds.size,
        scale: displayScale,
        mode: fitMode
      )
    else { return }
    let key = TrueImagePolicy.thumbnailKey(
      source: request.source, blurRadius: request.blurRadius, pixelSize: size)
    guard key != thumbnailKey else { return }
    thumbnailKey = key
    TrueImageThumbnails.shared.make(from: image, pixelSize: size, key: key) { [weak self] thumb in
      guard let self, let thumb, self.thumbnailKey == key, self.loaded?.request == request else {
        return
      }
      self.imageLayer.contents = thumb
    }
  }

  /// Catalog images are rasterised at the view's size so vector assets stay
  /// sharp on resize and tints resolve against the current traits.
  private func rasterise(_ image: UIImage, _ request: Request) {
    guard
      let raster = TrueImageResources.raster(
        image,
        size: bounds.size,
        scale: displayScale,
        tint: tint,
        mode: fitMode,
        traits: traitCollection
      )
    else {
      // Zero bounds: layoutSubviews rasterises once there is a size.
      rasterSize = .zero
      return
    }
    rasterSize = bounds.size
    interruptFade()
    imageLayer.contentsGravity = .resize
    imageLayer.contents = raster.image
    imageLayer.opacity = 1
    if reportedRequest != request {
      reportedRequest = request
      onLoad?(raster.pixelSize.width, raster.pixelSize.height, request.source)
      onDisplay?()
      onDisplayEnd?()
    }
  }
}

private final class FadeDelegate: NSObject, CAAnimationDelegate {
  private let completion: (Bool) -> Void

  init(_ completion: @escaping (Bool) -> Void) {
    self.completion = completion
  }

  func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
    completion(flag)
  }
}
