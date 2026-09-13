#import "TrueImageResources.h"

@implementation TrueImageResources

+ (UIImage *)imageNamed:(NSString *)name traits:(UITraitCollection *)traits
{
  return [UIImage imageNamed:name inBundle:NSBundle.mainBundle compatibleWithTraitCollection:traits];
}

+ (CGImageRef)rasterize:(UIImage *)image
                   size:(CGSize)size
                  scale:(CGFloat)scale
                   tint:(UIColor *)tint
                   mode:(TrueImageFitMode)mode
                 traits:(UITraitCollection *)traits
              pixelSize:(CGSize *)pixelSize
{
  if (size.width <= 0 || size.height <= 0) {
    return NULL;
  }
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
  format.scale = scale;
  format.opaque = NO;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
  CGRect rect = TrueImageFitRect(CGRectMake(0, 0, size.width, size.height), image.size, mode);
  // Resolve dynamic colours against the current traits so a DynamicColorIOS
  // tint re-rasterises correctly on appearance changes.
  UIImage *drawn = image;
  if (tint) {
    drawn = [image imageWithTintColor:[tint resolvedColorWithTraitCollection:traits]
                        renderingMode:UIImageRenderingModeAlwaysOriginal];
  }
  UIImage *raster = [renderer imageWithActions:^(UIGraphicsImageRendererContext *_) {
    [drawn drawInRect:rect];
  }];
  if (pixelSize) {
    *pixelSize = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
  }
  return CGImageRetain(raster.CGImage);
}

@end
