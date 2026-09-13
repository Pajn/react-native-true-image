#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TrueImageLoadCompletion)(UIImage *_Nullable image, BOOL fromMemory, NSString *_Nullable error);

/// One URL to warm the cache with, plus the headers to send for it.
@interface TrueImagePrefetchRequest : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *headers;
+ (instancetype)requestWithURL:(NSURL *)url headers:(nullable NSDictionary<NSString *, NSString *> *)headers;
@end

/// The single place that knows how an image request is built, so that a
/// prefetch and a view mounting later produce the identical cache key and
/// the view's load becomes a synchronous memory hit.
@interface TrueImageLoader : NSObject

/// Idempotent. Registers the WebP coder and caps the memory cache.
+ (void)configureOnce;

/// Returns a cancellable token. A memory hit calls `completion` synchronously.
/// Headers are sent with the request and are not part of the cache key.
/// A blurred load shrinks the cached original by `blurDownscale` before
/// blurring; see TrueImageBlurTransformer and TrueImageBlurDownscaleFactor.
+ (nullable id)loadURL:(NSURL *)url
            blurRadius:(CGFloat)blurRadius
         blurDownscale:(CGFloat)blurDownscale
               headers:(nullable NSDictionary<NSString *, NSString *> *)headers
            completion:(TrueImageLoadCompletion)completion;

+ (void)cancel:(nullable id)token;

/// Warms the cache with the exact request `loadURL:` makes. `ok` is false if
/// any URL failed.
+ (void)prefetch:(NSArray<TrueImagePrefetchRequest *> *)requests completion:(void (^)(BOOL ok))completion;

/// Replaces the network layer (an `id<SDImageLoader>`) for tests. nil
/// restores the default downloader. The shared image cache is kept.
+ (void)setImageLoaderForTesting:(nullable id)loader;

@end

NS_ASSUME_NONNULL_END
