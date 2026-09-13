#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Pure geometry and policy shared by the view, the thumbnail tier and the
/// unit tests. Nothing here touches UIKit so it runs on any Apple host.

typedef NS_ENUM(NSInteger, TrueImageFitMode) {
  TrueImageFitModeCover,
  TrueImageFitModeContain,
  TrueImageFitModeStretch,
  TrueImageFitModeCenter,
};

typedef NS_ENUM(NSInteger, TrueImageFadeKeyPath) {
  TrueImageFadeKeyPathOpacity,
  TrueImageFadeKeyPathContents,
};

/// The rect an image of `intrinsic` size occupies inside `bounds`. Cover
/// overflows, contain insets, both are centred. Stretch fills the bounds,
/// center draws at intrinsic size. A degenerate intrinsic size falls back to
/// the full bounds.
FOUNDATION_EXPORT CGRect TrueImageFitRect(CGRect bounds, CGSize intrinsic, TrueImageFitMode mode);

/// Pixel size to resample a decoded image to when it is drawn far below its
/// own size. Returns NO when no thumbnail is worth making: the view has no
/// size, the mode does not scale, or the image is under twice the drawn size
/// on either axis.
FOUNDATION_EXPORT BOOL TrueImageThumbnailPixelSize(
    CGSize imagePixels, CGSize drawnPoints, CGFloat scale, TrueImageFitMode mode, CGSize *outSize);

/// Cache key for a resampled thumbnail. Varies with the source, the blur and
/// the target size so a resize or a blur change never reuses a stale one.
FOUNDATION_EXPORT NSString *TrueImageThumbnailKey(NSString *source, CGFloat blurRadius, CGSize pixelSize);

/// Memory cache ceiling: a sixteenth of physical memory, capped at 256 MB.
/// Set because low-memory devices running long sessions were being
/// terminated under the library default.
FOUNDATION_EXPORT NSUInteger TrueImageMemoryCacheCost(unsigned long long physicalMemory);

/// A fade softens an image arriving late; a cached image in an empty view is
/// not late and draws at once. Replacing a displayed image always crossfades
/// when a transition is set. Native resources never fade.
FOUNDATION_EXPORT BOOL TrueImageShouldFade(NSInteger transitionMs, BOOL fromMemory, BOOL hasContents, BOOL isResource);

/// An empty layer fades its opacity in; a layer that already shows an image
/// crossfades its contents so nothing double-composites.
FOUNDATION_EXPORT TrueImageFadeKeyPath TrueImageFadeKeyPathFor(BOOL hasContents);

FOUNDATION_EXPORT NSString *TrueImageFadeKeyPathName(TrueImageFadeKeyPath keyPath);

FOUNDATION_EXPORT NSTimeInterval TrueImageFadeDuration(NSInteger transitionMs);

/// nil for a scheme-less name so the caller takes the native resource
/// branch; accepts `file://` paths containing spaces.
FOUNDATION_EXPORT NSURL *_Nullable TrueImageURLFromSource(NSString *source);

NS_ASSUME_NONNULL_END
