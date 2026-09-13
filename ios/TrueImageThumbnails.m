#import "TrueImageThumbnails.h"

@implementation TrueImageThumbnails {
  NSCache<NSString *, id> *_cache;
  dispatch_queue_t _queue;
}

+ (TrueImageThumbnails *)shared
{
  static TrueImageThumbnails *shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [TrueImageThumbnails new];
  });
  return shared;
}

- (instancetype)init
{
  if (self = [super init]) {
    _cache = [NSCache new];
    _cache.countLimit = 64;
    _queue = dispatch_queue_create("TrueImage.thumbnails", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(_queue, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
  }
  return self;
}

- (CGImageRef)cachedForKey:(NSString *)key
{
  return (__bridge CGImageRef)[_cache objectForKey:key];
}

- (void)makeFromImage:(UIImage *)image
            pixelSize:(CGSize)pixelSize
                  key:(NSString *)key
           completion:(void (^)(CGImageRef))completion
{
  CGImageRef hit = [self cachedForKey:key];
  if (hit) {
    completion(hit);
    return;
  }
  NSCache *cache = _cache;
  dispatch_async(_queue, ^{
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
    format.scale = 1;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:pixelSize format:format];
    UIImage *thumb = [renderer imageWithActions:^(UIGraphicsImageRendererContext *_) {
      [image drawInRect:CGRectMake(0, 0, pixelSize.width, pixelSize.height)];
    }];
    CGImageRef cg = thumb.CGImage;
    if (cg) {
      [cache setObject:(__bridge id)cg forKey:key];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(cg);
    });
  });
}

@end
