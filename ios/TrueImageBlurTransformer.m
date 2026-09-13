#import "TrueImageBlurTransformer.h"

#import "TrueImagePolicy.h"

@implementation TrueImageBlurTransformer

+ (instancetype)transformerWithRadius:(CGFloat)blurRadius downscale:(CGFloat)downscale
{
  TrueImageBlurTransformer *transformer = [TrueImageBlurTransformer new];
  transformer->_blurRadius = blurRadius;
  transformer->_downscale = MAX(1, downscale);
  return transformer;
}

- (NSString *)transformerKey
{
  return [NSString stringWithFormat:@"TrueImageBlur(%g,%g)", (double)_blurRadius, (double)_downscale];
}

- (UIImage *)transformedImageWithImage:(UIImage *)image forKey:(NSString *)key
{
  // `sd_blurredImageWithRadius:` takes points and multiplies by the image
  // scale; the radius here is in pixels.
  if (_downscale <= 1) {
    return [image sd_blurredImageWithRadius:_blurRadius / image.scale];
  }
  CGSize pixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
  CGSize small = TrueImageBlurDownscaleSize(pixels, _downscale);
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
  format.scale = 1;
  format.opaque = NO;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:small format:format];
  UIImage *shrunk = [renderer imageWithActions:^(UIGraphicsImageRendererContext *_) {
    [image drawInRect:CGRectMake(0, 0, small.width, small.height)];
  }];
  return [shrunk sd_blurredImageWithRadius:_blurRadius / _downscale];
}

@end
