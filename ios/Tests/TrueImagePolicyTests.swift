import CoreGraphics
import XCTest

@testable import TrueImagePolicy

final class FitRectTests: XCTestCase {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

  func testCoverOverflowsAndCentres() {
    let rect = TrueImagePolicy.fitRect(bounds: bounds, intrinsic: CGSize(width: 200, height: 100), mode: .cover)
    XCTAssertEqual(rect, CGRect(x: -50, y: 0, width: 200, height: 100))
  }

  func testContainInsetsAndCentres() {
    let rect = TrueImagePolicy.fitRect(bounds: bounds, intrinsic: CGSize(width: 200, height: 100), mode: .contain)
    XCTAssertEqual(rect, CGRect(x: 0, y: 25, width: 100, height: 50))
  }

  func testStretchFillsBounds() {
    let rect = TrueImagePolicy.fitRect(bounds: bounds, intrinsic: CGSize(width: 200, height: 100), mode: .stretch)
    XCTAssertEqual(rect, bounds)
  }

  func testCenterDrawsAtIntrinsicSize() {
    let rect = TrueImagePolicy.fitRect(bounds: bounds, intrinsic: CGSize(width: 40, height: 20), mode: .center)
    XCTAssertEqual(rect, CGRect(x: 30, y: 40, width: 40, height: 20))
  }

  func testDegenerateIntrinsicFallsBackToBounds() {
    XCTAssertEqual(TrueImagePolicy.fitRect(bounds: bounds, intrinsic: .zero, mode: .cover), bounds)
    XCTAssertEqual(TrueImagePolicy.fitRect(bounds: bounds, intrinsic: CGSize(width: -1, height: 10), mode: .contain), bounds)
  }
}

final class ThumbnailTests: XCTestCase {
  func testCoverDrawnFarBelowItsSize() {
    // 1200 px square cover in a 60 pt cell at 2x = 120 px → resample to 120.
    let size = TrueImagePolicy.thumbnailPixelSize(
      imagePixels: CGSize(width: 1200, height: 1200),
      drawnPoints: CGSize(width: 60, height: 60),
      scale: 2,
      mode: .cover
    )
    XCTAssertEqual(size, CGSize(width: 120, height: 120))
  }

  func testNoThumbnailUnderTwiceRatio() {
    let size = TrueImagePolicy.thumbnailPixelSize(
      imagePixels: CGSize(width: 200, height: 200),
      drawnPoints: CGSize(width: 60, height: 60),
      scale: 2,
      mode: .cover
    )
    XCTAssertNil(size)
  }

  func testKeepsAspectRatioForCoverAndContain() {
    let image = CGSize(width: 2000, height: 1000)
    let drawn = CGSize(width: 100, height: 100)
    let cover = TrueImagePolicy.thumbnailPixelSize(imagePixels: image, drawnPoints: drawn, scale: 1, mode: .cover)
    let contain = TrueImagePolicy.thumbnailPixelSize(imagePixels: image, drawnPoints: drawn, scale: 1, mode: .contain)
    XCTAssertEqual(cover, CGSize(width: 200, height: 100))
    XCTAssertEqual(contain, CGSize(width: 100, height: 50))
  }

  func testZeroSizeViewAsksForNothing() {
    XCTAssertNil(
      TrueImagePolicy.thumbnailPixelSize(
        imagePixels: CGSize(width: 1000, height: 1000), drawnPoints: .zero, scale: 2, mode: .cover))
  }

  func testCenterNeverResamples() {
    XCTAssertNil(
      TrueImagePolicy.thumbnailPixelSize(
        imagePixels: CGSize(width: 1000, height: 1000), drawnPoints: CGSize(width: 10, height: 10), scale: 1,
        mode: .center))
  }

  func testKeyVariesWithSourceBlurAndSize() {
    let a = TrueImagePolicy.thumbnailKey(source: "https://x/a.jpg", blurRadius: 0, pixelSize: CGSize(width: 100, height: 100))
    let b = TrueImagePolicy.thumbnailKey(source: "https://x/b.jpg", blurRadius: 0, pixelSize: CGSize(width: 100, height: 100))
    let c = TrueImagePolicy.thumbnailKey(source: "https://x/a.jpg", blurRadius: 25, pixelSize: CGSize(width: 100, height: 100))
    let d = TrueImagePolicy.thumbnailKey(source: "https://x/a.jpg", blurRadius: 0, pixelSize: CGSize(width: 200, height: 200))
    XCTAssertEqual(Set([a, b, c, d]).count, 4)
    XCTAssertEqual(a, TrueImagePolicy.thumbnailKey(source: "https://x/a.jpg", blurRadius: 0, pixelSize: CGSize(width: 100, height: 100)))
  }
}

final class FadePolicyTests: XCTestCase {
  func testMemoryHitIntoEmptyViewDrawsAtOnce() {
    XCTAssertFalse(TrueImagePolicy.shouldFade(transitionMs: 300, fromMemory: true, hasContents: false, isResource: false))
  }

  func testLateImageIntoEmptyViewFades() {
    XCTAssertTrue(TrueImagePolicy.shouldFade(transitionMs: 300, fromMemory: false, hasContents: false, isResource: false))
  }

  func testReplacingDisplayedImageAlwaysCrossfades() {
    XCTAssertTrue(TrueImagePolicy.shouldFade(transitionMs: 300, fromMemory: true, hasContents: true, isResource: false))
  }

  func testZeroTransitionNeverFades() {
    XCTAssertFalse(TrueImagePolicy.shouldFade(transitionMs: 0, fromMemory: false, hasContents: true, isResource: false))
  }

  func testResourcesNeverFade() {
    XCTAssertFalse(TrueImagePolicy.shouldFade(transitionMs: 300, fromMemory: false, hasContents: false, isResource: true))
  }

  func testKeyPathAndDuration() {
    XCTAssertEqual(TrueImagePolicy.fadeKeyPath(hasContents: false), .opacity)
    XCTAssertEqual(TrueImagePolicy.fadeKeyPath(hasContents: true), .contents)
    XCTAssertEqual(TrueImagePolicy.fadeDuration(transitionMs: 600), 0.6)
  }
}

final class LoaderPolicyTests: XCTestCase {
  func testMemoryCacheCost() {
    XCTAssertEqual(TrueImagePolicy.memoryCacheCost(physicalMemory: 2 * 1024 * 1024 * 1024), 128 * 1024 * 1024)
    XCTAssertEqual(TrueImagePolicy.memoryCacheCost(physicalMemory: 8 * 1024 * 1024 * 1024), 256 * 1024 * 1024)
  }

  func testRemoteURLPassesThrough() {
    XCTAssertEqual(
      TrueImagePolicy.url(from: "https://cdn.example.com/a.jpg?w=300")?.absoluteString,
      "https://cdn.example.com/a.jpg?w=300")
  }

  func testFileURLWithSpaceIsAccepted() {
    let url = TrueImagePolicy.url(from: "file:///var/mobile/My Cover.png")
    XCTAssertEqual(url?.scheme, "file")
    XCTAssertEqual(url?.lastPathComponent, "My Cover.png")
  }

  func testSchemelessIsNil() {
    XCTAssertNil(TrueImagePolicy.url(from: "ic_play"))
    XCTAssertNil(TrueImagePolicy.url(from: "cover fallback"))
  }
}
