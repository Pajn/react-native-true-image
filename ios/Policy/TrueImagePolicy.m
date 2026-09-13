#import "TrueImagePolicy.h"

CGRect TrueImageFitRect(CGRect bounds, CGSize intrinsic, TrueImageFitMode mode)
{
  if (intrinsic.width <= 0 || intrinsic.height <= 0 || bounds.size.width <= 0 || bounds.size.height <= 0) {
    return bounds;
  }
  CGSize size;
  switch (mode) {
    case TrueImageFitModeStretch:
      return bounds;
    case TrueImageFitModeCenter:
      size = intrinsic;
      break;
    case TrueImageFitModeCover:
    case TrueImageFitModeContain: {
      CGFloat sx = bounds.size.width / intrinsic.width;
      CGFloat sy = bounds.size.height / intrinsic.height;
      CGFloat scale = mode == TrueImageFitModeCover ? MAX(sx, sy) : MIN(sx, sy);
      size = CGSizeMake(intrinsic.width * scale, intrinsic.height * scale);
      break;
    }
  }
  return CGRectMake(
      CGRectGetMidX(bounds) - size.width / 2, CGRectGetMidY(bounds) - size.height / 2, size.width, size.height);
}

BOOL TrueImageThumbnailPixelSize(
    CGSize imagePixels, CGSize drawnPoints, CGFloat scale, TrueImageFitMode mode, CGSize *outSize)
{
  if (drawnPoints.width <= 0 || drawnPoints.height <= 0 || scale <= 0 || imagePixels.width <= 0 ||
      imagePixels.height <= 0 || mode == TrueImageFitModeCenter) {
    return NO;
  }
  CGRect drawnPixels = CGRectMake(0, 0, drawnPoints.width * scale, drawnPoints.height * scale);
  CGSize target = TrueImageFitRect(drawnPixels, imagePixels, mode).size;
  if (imagePixels.width < target.width * 2 || imagePixels.height < target.height * 2) {
    return NO;
  }
  if (outSize) {
    *outSize = CGSizeMake(ceil(target.width), ceil(target.height));
  }
  return YES;
}

NSString *TrueImageThumbnailKey(NSString *source, CGFloat blurRadius, CGFloat blurDownscale, CGSize pixelSize)
{
  return [NSString stringWithFormat:@"%@|b%g|d%g|%dx%d",
                                    source,
                                    (double)blurRadius,
                                    (double)blurDownscale,
                                    (int)pixelSize.width,
                                    (int)pixelSize.height];
}

CGFloat const TrueImageDefaultBlurPixelsPerRadius = 2;

CGFloat TrueImageBlurDownscaleFactor(CGFloat blurRadius, CGFloat pixelsPerRadius)
{
  if (blurRadius <= 0 || pixelsPerRadius <= 0) {
    return 1;
  }
  return MAX(1, blurRadius / pixelsPerRadius);
}

CGSize TrueImageBlurDownscaleSize(CGSize pixels, CGFloat factor)
{
  if (factor <= 1) {
    return pixels;
  }
  return CGSizeMake(MAX(1, ceil(pixels.width / factor)), MAX(1, ceil(pixels.height / factor)));
}

NSUInteger TrueImageMemoryCacheCost(unsigned long long physicalMemory)
{
  unsigned long long const cap = 256ull * 1024 * 1024;
  return (NSUInteger)MIN(physicalMemory / 16, cap);
}

BOOL TrueImageShouldFade(NSInteger transitionMs, BOOL fromMemory, BOOL hasContents, BOOL isResource)
{
  if (transitionMs <= 0 || isResource) {
    return NO;
  }
  return !(fromMemory && !hasContents);
}

TrueImageFadeKeyPath TrueImageFadeKeyPathFor(BOOL hasContents)
{
  return hasContents ? TrueImageFadeKeyPathContents : TrueImageFadeKeyPathOpacity;
}

NSString *TrueImageFadeKeyPathName(TrueImageFadeKeyPath keyPath)
{
  return keyPath == TrueImageFadeKeyPathContents ? @"contents" : @"opacity";
}

NSTimeInterval TrueImageFadeDuration(NSInteger transitionMs)
{
  return (NSTimeInterval)transitionMs / 1000.0;
}

NSURL *TrueImageURLFromSource(NSString *source)
{
  NSURLComponents *components = [NSURLComponents componentsWithString:source];
  if (components.scheme.length > 0) {
    return components.URL;
  }
  // NSURLComponents rejects unescaped spaces; retry with them encoded so a
  // `file:///…/My Cover.png` still parses. Anything without a scheme is a
  // resource name.
  NSString *escaped = [source stringByReplacingOccurrencesOfString:@" " withString:@"%20"];
  if ([escaped isEqualToString:source]) {
    return nil;
  }
  NSURLComponents *retry = [NSURLComponents componentsWithString:escaped];
  return retry.scheme.length > 0 ? retry.URL : nil;
}
