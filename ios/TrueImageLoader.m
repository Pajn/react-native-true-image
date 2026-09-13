#import "TrueImageLoader.h"

#import <SDWebImage/SDWebImage.h>

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

static SDWebImageContext *ContextForBlur(CGFloat blurRadius)
{
  if (blurRadius <= 0) {
    return BaseContext();
  }
  // The transformer gets its own cache key; the sharp original stays cached
  // and is reused as the transform input.
  NSMutableDictionary *context = [BaseContext() mutableCopy];
  context[SDWebImageContextImageTransformer] = [SDImageBlurTransformer transformerWithRadius:blurRadius];
  return context;
}

static id<SDImageLoader> gTestLoader;
static SDWebImageManager *gManager;
static SDWebImagePrefetcher *gPrefetcher;

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

/// Built on our manager on purpose: the shared prefetcher owns a separate
/// manager with its own options, so a view load would not share its result.
static SDWebImagePrefetcher *Prefetcher(void)
{
  if (!gPrefetcher) {
    gPrefetcher = [[SDWebImagePrefetcher alloc] initWithImageManager:Manager()];
    gPrefetcher.options = kOptions;
    gPrefetcher.context = BaseContext();
  }
  return gPrefetcher;
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

+ (id)loadURL:(NSURL *)url blurRadius:(CGFloat)blurRadius completion:(TrueImageLoadCompletion)completion
{
  return [Manager()
       loadImageWithURL:url
                options:kOptions
                context:ContextForBlur(blurRadius)
               progress:nil
              completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                if (!finished) {
                  return;
                }
                completion(image, cacheType == SDImageCacheTypeMemory, error.localizedDescription);
              }];
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
  gPrefetcher = nil;
}

+ (void)prefetchURLs:(NSArray<NSURL *> *)urls completion:(void (^)(BOOL))completion
{
  if (urls.count == 0) {
    completion(YES);
    return;
  }
  [Prefetcher() prefetchURLs:urls
                    progress:nil
                   completed:^(NSUInteger finished, NSUInteger skipped) {
                     completion(skipped == 0);
                   }];
}

@end
