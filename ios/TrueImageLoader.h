#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TrueImageLoadCompletion)(UIImage *_Nullable image, BOOL fromMemory, NSString *_Nullable error);

/// The single place that knows how an image request is built, so that a
/// prefetch and a view mounting later produce the identical cache key and
/// the view's load becomes a synchronous memory hit. Objective-C because the
/// imaging library does not define a module Swift could import.
@interface TrueImageLoader : NSObject

/// Idempotent. Registers the WebP coder and caps the memory cache.
+ (void)configureOnceWithMaxMemoryCost:(NSUInteger)maxMemoryCost;

/// Returns a cancellable token. A memory hit calls `completion` synchronously.
+ (nullable id)loadURL:(NSURL *)url blurRadius:(CGFloat)blurRadius completion:(TrueImageLoadCompletion)completion;

+ (void)cancel:(nullable id)token;

/// Warms the cache with the exact request `loadURL:` makes. `ok` is false if
/// any URL failed.
+ (void)prefetchURLs:(NSArray<NSURL *> *)urls completion:(void (^)(BOOL ok))completion;

@end

NS_ASSUME_NONNULL_END
