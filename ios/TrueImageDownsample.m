#import "TrueImageDownsample.h"
#import "TrueImageBlurTransformer.h"
#import <ImageIO/ImageIO.h>

@implementation TrueImageDownsample {
  CGSize _originalPixels;
  CGSize _decodedPixels;
}

- (CGSize)originalPixels
{
  return _originalPixels;
}

- (CGSize)decodedPixels
{
  return _decodedPixels;
}

- (BOOL)canDecodeFromData:(NSData *)data
{
  return [SDImageCodersManager.sharedManager canDecodeFromData:data];
}

- (UIImage *)decodedImageWithData:(NSData *)data options:(SDImageCoderOptions *)options
{
  // ImageIO reads headers without decoding pixels, including our WebP coder's format.
  CGImageSourceRef source = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
  NSDictionary *properties = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
  if (source) CFRelease(source);
  CGSize original = CGSizeMake([properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue],
                               [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue]);
  NSInteger orientation = [properties[(__bridge NSString *)kCGImagePropertyOrientation] integerValue];
  CGSize display = orientation >= 5 ? CGSizeMake(_pixelSize.height, _pixelSize.width) : _pixelSize;
  CGSize target = TrueImageDecodePixelSize(original, display, _fitMode, _threshold);
  NSMutableDictionary *decode = [options mutableCopy] ?: [NSMutableDictionary new];
  decode[SDImageCoderDecodeThumbnailPixelSize] = [NSValue valueWithCGSize:target];
  decode[SDImageCoderDecodePreserveAspectRatio] = @YES;
  UIImage *image = [SDImageCodersManager.sharedManager decodedImageWithData:data options:decode];
  _originalPixels = original;
  _decodedPixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
  return image;
}

- (NSString *)transformerKey
{
  return [NSString stringWithFormat:@"true-image-decode-v1:%ld:%.17g:%.17g:%.17g",
          (long)_fitMode, (double)_threshold, (double)_blurRadius, (double)_blurDownscale];
}

- (UIImage *)transformedImageWithImage:(UIImage *)image forKey:(NSString *)key
{
  if (_blurRadius <= 0) return image;
  CGSize original = _originalPixels;
  CGFloat decodedLong = MAX(image.size.width, image.size.height) * image.scale;
  CGFloat originalLong = MAX(original.width, original.height);
  CGFloat scale = originalLong > 0 ? MIN(1, decodedLong / originalLong) : 1;
  // Preserve source-pixel blur radius while accounting for decode-time shrink.
  id<SDImageTransformer> blur = [TrueImageBlurTransformer transformerWithRadius:_blurRadius * scale
                                                                    downscale:MAX(1, _blurDownscale * scale)];
  return [blur transformedImageWithImage:image forKey:key];
}

- (BOOL)canEncodeToFormat:(SDImageFormat)format
{
  return [SDImageCodersManager.sharedManager canEncodeToFormat:format];
}

- (NSData *)encodedDataWithImage:(UIImage *)image format:(SDImageFormat)format options:(SDImageCoderOptions *)options
{
  return [SDImageCodersManager.sharedManager encodedDataWithImage:image format:format options:options];
}
@end
