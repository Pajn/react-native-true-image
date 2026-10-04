#import "TrueImageLoader.h"

#import <SDWebImage/SDWebImage.h>

#import "TrueImageBlurTransformer.h"
#import "TrueImageDownsample.h"
#import "TrueImagePolicy.h"
#import "TrueImageWebPCoder.h"

/// `.retryFailed` keeps a URL that failed once (a 404 during a network
/// blip) from being blacklisted for the rest of the process.
static SDWebImageOptions const kOptions = SDWebImageRetryFailed;

static SDWebImageContext *BaseContext(void)
{
  static SDWebImageContext *context;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    context = @{
      SDWebImageContextQueryCacheType : @(SDImageCacheTypeAll),
      SDWebImageContextStoreCacheType : @(SDImageCacheTypeAll),
    };
  });
  return context;
}

static SDWebImageContext *ContextFor(
    CGFloat blurRadius, CGFloat blurDownscale, NSDictionary<NSString *, NSString *> *headers,
    CGSize pixelSize, TrueImageFitMode fitMode, CGFloat threshold)
{
  BOOL sized = pixelSize.width > 0 && pixelSize.height > 0 && threshold > 0 && fitMode != TrueImageFitModeCenter;
  if (!sized && blurRadius <= 0 && headers.count == 0) {
    return BaseContext();
  }
  NSMutableDictionary *context = [BaseContext() mutableCopy];
  if (blurRadius > 0) {
    // The transformer gets its own cache key; the sharp original stays cached
    // and is reused as the transform input.
    context[SDWebImageContextImageTransformer] =
        [TrueImageBlurTransformer transformerWithRadius:blurRadius downscale:blurDownscale];
  }
  if (sized) {
    TrueImageDownsample *policy = [TrueImageDownsample new];
    policy.pixelSize = pixelSize;
    policy.fitMode = fitMode;
    policy.threshold = threshold;
    policy.blurRadius = blurRadius;
    policy.blurDownscale = blurDownscale;
    context[SDWebImageContextImageCoder] = policy;
    context[SDWebImageContextImageTransformer] = policy;
    context[SDWebImageContextImageThumbnailPixelSize] = [NSValue valueWithCGSize:pixelSize];
    // Read the same original disk data without putting a reduced bitmap in
    // the URL-only memory entry (SDWebImage otherwise writes it back there).
    static SDImageCache *originalCache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      SDImageCache *shared = SDImageCache.sharedImageCache;
      SDImageCacheConfig *config = [shared.config copy];
      config.shouldCacheImagesInMemory = NO;
      originalCache = [[SDImageCache alloc] initWithNamespace:shared.diskCachePath.lastPathComponent
                                         diskCacheDirectory:shared.diskCachePath.stringByDeletingLastPathComponent
                                                     config:config];
    });
    context[SDWebImageContextOriginalImageCache] = originalCache;
  }
  if (headers.count > 0) {
    // A request modifier is not part of the cache key: the same URL is one
    // image whatever headers fetched it.
    context[SDWebImageContextDownloadRequestModifier] =
        [[SDWebImageDownloaderRequestModifier alloc] initWithHeaders:headers];
  }
  return context;
}

@implementation TrueImagePrefetchRequest
+ (instancetype)requestWithURL:(NSURL *)url headers:(NSDictionary<NSString *, NSString *> *)headers
{
  TrueImagePrefetchRequest *request = [TrueImagePrefetchRequest new];
  request.url = url;
  request.downsampleThreshold = 2;
  request.headers = headers;
  return request;
}
@end

static id<SDImageLoader> gTestLoader;
static SDWebImageManager *gManager;

/// One manager for views and prefetches, sharing the app-wide image cache.
/// Owning it rather than using the shared manager keeps a single failed-URL
/// set (which `.retryFailed` disables anyway) and gives tests a place to
/// swap the network layer.
static SDWebImageManager *Manager(void)
{
  if (!gManager) {
    id<SDImageLoader> loader = gTestLoader ?: SDWebImageManager.defaultImageLoader;
    gManager = [[SDWebImageManager alloc] initWithCache:SDImageCache.sharedImageCache loader:loader];
  }
  return gManager;
}

// A bounded index of cache keys and geometry; SDWebImage retains the images.
static NSCache<NSString *, NSArray<NSDictionary *> *> *VariantIndex(void)
{
  static NSCache *index;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ index = [NSCache new]; index.countLimit = 256; });
  return index;
}

static void RecordVariant(NSURL *url, SDWebImageContext *context, UIImage *image)
{
  TrueImageDownsample *policy = context[SDWebImageContextImageCoder];
  if (![policy isKindOfClass:TrueImageDownsample.class] || !image || policy.decodedPixels.width <= 0) return;
  NSString *key = [Manager() cacheKeyForURL:url context:context];
  NSDictionary *entry = @{@"key": key, @"policy": policy.transformerKey,
    @"size": [NSValue valueWithCGSize:policy.pixelSize], @"decoded": [NSValue valueWithCGSize:policy.decodedPixels],
    @"original": @(MAX(policy.decodedPixels.width, policy.decodedPixels.height) >=
                   MAX(policy.originalPixels.width, policy.originalPixels.height))};
  @synchronized (VariantIndex()) {
    NSMutableArray *entries = [[VariantIndex() objectForKey:url.absoluteString] mutableCopy] ?: [NSMutableArray new];
    NSIndexSet *old = [entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
      return [item[@"key"] isEqual:key];
    }];
    [entries removeObjectsAtIndexes:old];
    [entries addObject:entry];
    if (entries.count > 8) [entries removeObjectAtIndex:0];
    [VariantIndex() setObject:entries forKey:url.absoluteString];
  }
}

@implementation TrueImageLoader

+ (void)configureOnce
{
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    SDImageCache.sharedImageCache.config.maxMemoryCost =
        TrueImageMemoryCacheCost(NSProcessInfo.processInfo.physicalMemory);
    // WebP is not decoded by default; most image CDNs serve it.
    [SDImageCodersManager.sharedManager addCoder:TrueImageWebPCoder.sharedCoder];
  });
}

+ (id)loadURL:(NSURL *)url
     blurRadius:(CGFloat)blurRadius
  blurDownscale:(CGFloat)blurDownscale
        headers:(NSDictionary<NSString *, NSString *> *)headers
      cacheOnly:(BOOL)cacheOnly
     completion:(TrueImageLoadCompletion)completion
{
  return [self loadURL:url blurRadius:blurRadius blurDownscale:blurDownscale headers:headers cacheOnly:cacheOnly
             pixelSize:CGSizeZero fitMode:TrueImageFitModeCover downsampleThreshold:0 completion:completion];
}

+ (id)loadURL:(NSURL *)url
     blurRadius:(CGFloat)blurRadius
  blurDownscale:(CGFloat)blurDownscale
        headers:(NSDictionary<NSString *, NSString *> *)headers
      cacheOnly:(BOOL)cacheOnly
      pixelSize:(CGSize)pixelSize
        fitMode:(TrueImageFitMode)fitMode
 downsampleThreshold:(CGFloat)threshold
     completion:(TrueImageLoadCompletion)completion
{
  SDWebImageContext *context = ContextFor(blurRadius, blurDownscale, headers, pixelSize, fitMode, threshold);
  return [Manager()
       loadImageWithURL:url
                options:cacheOnly ? (kOptions | SDWebImageFromCacheOnly) : kOptions
                context:context
               progress:nil
              completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                if (!finished) {
                  return;
                }
                RecordVariant(url, context, image);
                completion(image, cacheType == SDImageCacheTypeMemory, error.localizedDescription);
              }];
}

+ (CGSize)compatiblePixelSizeForURL:(NSURL *)url pixelSize:(CGSize)pixelSize fitMode:(TrueImageFitMode)fitMode
              downsampleThreshold:(CGFloat)threshold blurRadius:(CGFloat)radius blurDownscale:(CGFloat)downscale
{
  if (pixelSize.width <= 0 || pixelSize.height <= 0 || threshold <= 0 || fitMode == TrueImageFitModeCenter) return pixelSize;
  TrueImageDownsample *policy = [TrueImageDownsample new];
  policy.fitMode = fitMode; policy.threshold = threshold; policy.blurRadius = radius; policy.blurDownscale = downscale;
  NSArray *entries;
  @synchronized (VariantIndex()) { entries = [VariantIndex() objectForKey:url.absoluteString]; }
  for (NSDictionary *entry in entries.reverseObjectEnumerator) {
    if (![entry[@"policy"] isEqual:policy.transformerKey]) continue;
    CGSize decoded = [entry[@"decoded"] CGSizeValue];
    CGFloat sx = pixelSize.width / decoded.width, sy = pixelSize.height / decoded.height;
    CGFloat scale = fitMode == TrueImageFitModeContain ? MIN(sx, sy) : MAX(sx, sy);
    if ((scale <= 1 || [entry[@"original"] boolValue]) && scale >= 1 / threshold &&
        [SDImageCache.sharedImageCache imageFromMemoryCacheForKey:entry[@"key"]]) {
      return [entry[@"size"] CGSizeValue];
    }
  }
  return pixelSize;
}

+ (void)cancel:(id)token
{
  if ([token conformsToProtocol:@protocol(SDWebImageOperation)]) {
    [(id<SDWebImageOperation>)token cancel];
  }
}

+ (void)setImageLoaderForTesting:(id)loader
{
  gTestLoader = loader;
  gManager = nil;
}

/// Goes through the same manager, options and context as a view load, so
/// the two produce one cache entry. Each request carries its own headers,
/// which a shared prefetcher could not do.
+ (void)prefetch:(NSArray<TrueImagePrefetchRequest *> *)requests completion:(void (^)(BOOL))completion
{
  NSUInteger total = requests.count;
  if (total == 0) {
    completion(YES);
    return;
  }
  __block NSUInteger finishedCount = 0;
  __block BOOL ok = YES;
  for (TrueImagePrefetchRequest *request in requests) {
    [self loadURL:request.url blurRadius:0 blurDownscale:1 headers:request.headers cacheOnly:NO
         pixelSize:request.pixelSize fitMode:request.fitMode downsampleThreshold:request.downsampleThreshold
        completion:^(UIImage *image, BOOL fromMemory, NSString *error) {
          if (!image) ok = NO;
          if (++finishedCount == total) completion(ok);
        }];
  }
}

@end
