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

static SDWebImageContext *ContextFor(CGFloat blurRadius, NSDictionary<NSString *, NSString *> *headers)
{
  if (blurRadius <= 0 && headers.count == 0) {
    return BaseContext();
  }
  NSMutableDictionary *context = [BaseContext() mutableCopy];
  if (blurRadius > 0) {
    // The transformer gets its own cache key; the sharp original stays cached
    // and is reused as the transform input.
    context[SDWebImageContextImageTransformer] = [SDImageBlurTransformer transformerWithRadius:blurRadius];
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
        headers:(NSDictionary<NSString *, NSString *> *)headers
     completion:(TrueImageLoadCompletion)completion
{
  return [Manager()
       loadImageWithURL:url
                options:kOptions
                context:ContextFor(blurRadius, headers)
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
    [Manager() loadImageWithURL:request.url
                        options:kOptions
                        context:ContextFor(0, request.headers)
                       progress:nil
                      completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                        if (!finished) {
                          return;
                        }
                        if (!image) {
                          ok = NO;
                        }
                        if (++finishedCount == total) {
                          completion(ok);
                        }
                      }];
  }
}

@end
