import CoreGraphics
import TrueImagePolicy
import XCTest

final class FitRectTests: XCTestCase {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

  func testCoverOverflowsAndCentres() {
    XCTAssertEqual(
      TrueImageFitRect(bounds, CGSize(width: 200, height: 100), .cover),
      CGRect(x: -50, y: 0, width: 200, height: 100))
  }

  func testContainInsetsAndCentres() {
    XCTAssertEqual(
      TrueImageFitRect(bounds, CGSize(width: 200, height: 100), .contain),
      CGRect(x: 0, y: 25, width: 100, height: 50))
  }

  func testStretchFillsBounds() {
    XCTAssertEqual(TrueImageFitRect(bounds, CGSize(width: 200, height: 100), .stretch), bounds)
  }

  func testCenterDrawsAtIntrinsicSize() {
    XCTAssertEqual(
      TrueImageFitRect(bounds, CGSize(width: 40, height: 20), .center),
      CGRect(x: 30, y: 40, width: 40, height: 20))
  }

  func testDegenerateIntrinsicFallsBackToBounds() {
    XCTAssertEqual(TrueImageFitRect(bounds, .zero, .cover), bounds)
    XCTAssertEqual(TrueImageFitRect(bounds, CGSize(width: -1, height: 10), .contain), bounds)
  }
}

final class ThumbnailTests: XCTestCase {
  private func thumbnail(_ image: CGSize, _ drawn: CGSize, scale: CGFloat, mode: TrueImageFitMode) -> CGSize? {
    var size = CGSize.zero
    return TrueImageThumbnailPixelSize(image, drawn, scale, mode, &size) ? size : nil
  }

  func testCoverDrawnFarBelowItsSize() {
    // 1200 px square cover in a 60 pt cell at 2x = 120 px → resample to 120.
    XCTAssertEqual(
      thumbnail(CGSize(width: 1200, height: 1200), CGSize(width: 60, height: 60), scale: 2, mode: .cover),
      CGSize(width: 120, height: 120))
  }

  func testNoThumbnailUnderTwiceRatio() {
    XCTAssertNil(thumbnail(CGSize(width: 200, height: 200), CGSize(width: 60, height: 60), scale: 2, mode: .cover))
  }

  func testKeepsAspectRatioForCoverAndContain() {
    let image = CGSize(width: 2000, height: 1000)
    let drawn = CGSize(width: 100, height: 100)
    XCTAssertEqual(thumbnail(image, drawn, scale: 1, mode: .cover), CGSize(width: 200, height: 100))
    XCTAssertEqual(thumbnail(image, drawn, scale: 1, mode: .contain), CGSize(width: 100, height: 50))
  }

  func testZeroSizeViewAsksForNothing() {
    XCTAssertNil(thumbnail(CGSize(width: 1000, height: 1000), .zero, scale: 2, mode: .cover))
  }

  func testCenterNeverResamples() {
    XCTAssertNil(thumbnail(CGSize(width: 1000, height: 1000), CGSize(width: 10, height: 10), scale: 1, mode: .center))
  }

  func testKeyVariesWithSourceBlurAndSize() {
    let size = CGSize(width: 100, height: 100)
    let a = TrueImageThumbnailKey("https://x/a.jpg", 0, 1, size)
    let b = TrueImageThumbnailKey("https://x/b.jpg", 0, 1, size)
    let c = TrueImageThumbnailKey("https://x/a.jpg", 25, 1, size)
    let d = TrueImageThumbnailKey("https://x/a.jpg", 0, 1, CGSize(width: 200, height: 200))
    let e = TrueImageThumbnailKey("https://x/a.jpg", 25, 12.5, size)
    XCTAssertEqual(Set([a, b, c, d, e]).count, 5)
    XCTAssertEqual(a, TrueImageThumbnailKey("https://x/a.jpg", 0, 1, size))
  }
}

final class BlurDownscaleTests: XCTestCase {
  func testDefaultKeepsTwoPixelsPerRadius() {
    XCTAssertEqual(TrueImageDefaultBlurPixelsPerRadius, 2)
    XCTAssertEqual(TrueImageBlurDownscaleFactor(100, TrueImageDefaultBlurPixelsPerRadius), 50)
  }

  func testMorePixelsPerRadiusShrinksLess() {
    XCTAssertEqual(TrueImageBlurDownscaleFactor(100, 4), 25)
  }

  func testNeverUpscales() {
    XCTAssertEqual(TrueImageBlurDownscaleFactor(1, 2), 1)
    XCTAssertEqual(TrueImageBlurDownscaleFactor(0, 2), 1)
  }

  func testZeroPixelsPerRadiusDisablesTheShrink() {
    XCTAssertEqual(TrueImageBlurDownscaleFactor(100, 0), 1)
    XCTAssertEqual(TrueImageBlurDownscaleFactor(100, -1), 1)
  }

  func testSizeRoundsUpAndStaysAtLeastOnePixel() {
    XCTAssertEqual(
      TrueImageBlurDownscaleSize(CGSize(width: 4000, height: 3000), 50), CGSize(width: 80, height: 60))
    XCTAssertEqual(TrueImageBlurDownscaleSize(CGSize(width: 101, height: 10), 50), CGSize(width: 3, height: 1))
    XCTAssertEqual(TrueImageBlurDownscaleSize(CGSize(width: 10, height: 10), 1), CGSize(width: 10, height: 10))
  }
}

final class FadePolicyTests: XCTestCase {
  func testMemoryHitIntoEmptyViewDrawsAtOnce() {
    XCTAssertFalse(TrueImageShouldFade(300, true, false, false))
  }

  func testLateImageIntoEmptyViewFades() {
    XCTAssertTrue(TrueImageShouldFade(300, false, false, false))
  }

  func testReplacingDisplayedImageAlwaysCrossfades() {
    XCTAssertTrue(TrueImageShouldFade(300, true, true, false))
  }

  func testZeroTransitionNeverFades() {
    XCTAssertFalse(TrueImageShouldFade(0, false, true, false))
  }

  func testResourcesNeverFade() {
    XCTAssertFalse(TrueImageShouldFade(300, false, false, true))
  }

  func testKeyPathAndDuration() {
    XCTAssertEqual(TrueImageFadeKeyPathFor(false), .opacity)
    XCTAssertEqual(TrueImageFadeKeyPathFor(true), .contents)
    XCTAssertEqual(TrueImageFadeKeyPathName(.opacity), "opacity")
    XCTAssertEqual(TrueImageFadeKeyPathName(.contents), "contents")
    XCTAssertEqual(TrueImageFadeDuration(600), 0.6)
  }
}

final class LoaderPolicyTests: XCTestCase {
  func testMemoryCacheCost() {
    XCTAssertEqual(TrueImageMemoryCacheCost(2 * 1024 * 1024 * 1024), 128 * 1024 * 1024)
    XCTAssertEqual(TrueImageMemoryCacheCost(8 * 1024 * 1024 * 1024), 256 * 1024 * 1024)
  }

  func testRemoteURLPassesThrough() {
    XCTAssertEqual(
      TrueImageURLFromSource("https://cdn.example.com/a.jpg?w=300")?.absoluteString,
      "https://cdn.example.com/a.jpg?w=300")
  }

  func testFileURLWithSpaceIsAccepted() {
    let url = TrueImageURLFromSource("file:///var/mobile/My Cover.png")
    XCTAssertEqual(url?.scheme, "file")
    XCTAssertEqual(url?.lastPathComponent, "My Cover.png")
  }

  func testSchemelessIsNil() {
    XCTAssertNil(TrueImageURLFromSource("ic_play"))
    XCTAssertNil(TrueImageURLFromSource("cover fallback"))
  }
}
