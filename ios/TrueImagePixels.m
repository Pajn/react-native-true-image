#import "TrueImagePixels.h"

#import "TrueImageLoader.h"
#import "TrueImagePolicy.h"
#import "TrueImageResources.h"

@implementation TrueImagePixels

+ (NSUInteger)maxSize
{
  return 256;
}

+ (void)loadSource:(NSString *)source
           headers:(NSDictionary<NSString *, NSString *> *)headers
              size:(NSUInteger)size
        completion:(void (^)(NSData *))completion
{
  dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
  if (size < 1 || size > self.maxSize) {
    dispatch_async(queue, ^{ completion(nil); });
    return;
  }
  NSURL *url = TrueImageURLFromSource(source);
  if (!url) {
    dispatch_async(queue, ^{
      UIImage *image = [TrueImageResources imageNamed:source traits:UITraitCollection.currentTraitCollection];
      completion(image ? [self rgbaFromImage:image size:size] : nil);
    });
    return;
  }
  // Decoded near the sample size like a view of that size would be.
  [TrueImageLoader loadURL:url
                blurRadius:0
             blurDownscale:1
                   headers:headers
                 cacheOnly:NO
                 pixelSize:CGSizeMake(size, size)
                   fitMode:TrueImageFitModeCover
       downsampleThreshold:1
                completion:^(UIImage *image, BOOL fromMemory, NSString *error) {
                  dispatch_async(queue, ^{
                    completion(image ? [self rgbaFromImage:image size:size] : nil);
                  });
                }];
}

+ (NSData *)rgbaFromImage:(UIImage *)image size:(NSUInteger)size
{
  if (size == 0 || image.size.width <= 0 || image.size.height <= 0) return nil;
  NSMutableData *data = [NSMutableData dataWithLength:size * size * 4];
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  // Bitmap contexts only draw premultiplied; the bytes are RGBA in memory.
  CGContextRef context = CGBitmapContextCreate(data.mutableBytes, size, size, 8, size * 4, space,
                                               kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(space);
  if (!context) return nil;
  CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
  // UIKit drawing honours the image orientation and draws catalog vectors.
  CGContextTranslateCTM(context, 0, size);
  CGContextScaleCTM(context, 1, -1);
  UIGraphicsPushContext(context);
  [image drawInRect:CGRectMake(0, 0, size, size)];
  UIGraphicsPopContext();
  CGContextRelease(context);

  uint8_t *bytes = data.mutableBytes;
  for (NSUInteger i = 0; i < data.length; i += 4) {
    uint8_t alpha = bytes[i + 3];
    if (alpha == 0 || alpha == 255) continue;
    for (NSUInteger c = 0; c < 3; c++) {
      bytes[i + c] = (uint8_t)MIN(255, (bytes[i + c] * 255 + alpha / 2) / alpha);
    }
  }
  return data;
}

@end
