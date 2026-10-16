#import "TrueImagePixels.h"

#import "TrueImageLoader.h"
#import "TrueImagePolicy.h"
#import "TrueImageResources.h"
#import "TrueImageVariants.h"

@implementation TrueImagePixels

+ (NSUInteger)maxSize
{
  return 256;
}

+ (void)loadSource:(NSString *)source
           headers:(NSDictionary<NSString *, NSString *> *)headers
              size:(NSUInteger)size
          cacheKey:(NSString *)cacheKey
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
  // The source itself from cache, then each cached variant, then the
  // network for the source; without a variant, straight to the last.
  NSMutableArray<NSURL *> *cached = [NSMutableArray new];
  if (cacheKey.length > 0) {
    TrueImageVariantChoice *choice = [TrueImageVariants choose:[TrueImageVariants variantsForKey:cacheKey]
                                                     excluding:source
                                                    viewPixels:CGSizeMake(size, size)
                                                       fitMode:TrueImageFitModeCover];
    for (TrueImageVariant *variant in [choice.sufficient arrayByAddingObjectsFromArray:choice.smaller]) {
      NSURL *variantURL = TrueImageURLFromSource(variant.url);
      if (variantURL) [cached addObject:variantURL];
    }
    if (cached.count > 0) [cached insertObject:url atIndex:0];
  }
  [self sample:url cached:cached index:0 headers:headers size:size cacheKey:cacheKey queue:queue completion:completion];
}

+ (void)sample:(NSURL *)url
        cached:(NSArray<NSURL *> *)cached
         index:(NSUInteger)index
       headers:(NSDictionary<NSString *, NSString *> *)headers
          size:(NSUInteger)size
      cacheKey:(NSString *)cacheKey
         queue:(dispatch_queue_t)queue
    completion:(void (^)(NSData *))completion
{
  BOOL fromCache = index < cached.count;
  NSURL *attempt = fromCache ? cached[index] : url;
  // Decoded near the sample size like a view of that size would be.
  [TrueImageLoader loadURL:attempt
                blurRadius:0
             blurDownscale:1
                   headers:headers
                 cacheOnly:fromCache
                 pixelSize:CGSizeMake(size, size)
                   fitMode:TrueImageFitModeCover
       downsampleThreshold:1
                  cacheKey:cacheKey
                completion:^(UIImage *image, BOOL fromMemory, NSString *error) {
                  if (!image && fromCache) {
                    if (![attempt isEqual:url]) {
                      [TrueImageVariants forgetURL:attempt.absoluteString forKey:cacheKey];
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                      [self sample:url cached:cached index:index + 1 headers:headers size:size cacheKey:cacheKey
                             queue:queue completion:completion];
                    });
                    return;
                  }
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
