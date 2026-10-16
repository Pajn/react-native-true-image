#import <UIKit/UIKit.h>

#import "TrueImagePolicy.h"

NS_ASSUME_NONNULL_BEGIN

/// One URL of a picture and that URL's full size in pixels.
@interface TrueImageVariant : NSObject
@property (nonatomic, copy, readonly) NSString *url;
@property (nonatomic, readonly) CGSize pixelSize;
+ (instancetype)variantWithURL:(NSString *)url pixelSize:(CGSize)pixelSize;
@end

/// The variants of a key split for one view: those that fill it without
/// upscaling, smallest first, and the rest, largest first.
@interface TrueImageVariantChoice : NSObject
@property (nonatomic, copy, readonly) NSArray<TrueImageVariant *> *sufficient;
@property (nonatomic, copy, readonly) NSArray<TrueImageVariant *> *smaller;
@end

/// cacheKey → the URLs known to hold that picture, each with its full pixel
/// size. Successful loads and prefetches with a cacheKey record here; views
/// read it to reuse a cached variant or to show a smaller one while theirs
/// loads. It holds no pixels and promises nothing about SDWebImage's caches:
/// every variant it suggests is checked with a cache-only request, and one
/// found evicted is forgotten.
///
/// Persisted as JSON in the app's caches directory so it outlives the
/// process, bounded to `maxKeys` keys in least-recently-used order and
/// `maxVariants` URLs per key. The file is read and written on a background
/// queue; an unreadable file is dropped and the index starts empty.
@interface TrueImageVariants : NSObject

@property (class, nonatomic, readonly) NSUInteger maxKeys;
@property (class, nonatomic, readonly) NSUInteger maxVariants;

/// Splits `variants` for a view needing `viewPixels` in `mode`, leaving out
/// `excluded` (the URL the view asked for).
+ (TrueImageVariantChoice *)choose:(NSArray<TrueImageVariant *> *)variants
                         excluding:(nullable NSString *)excluded
                        viewPixels:(CGSize)viewPixels
                           fitMode:(TrueImageFitMode)mode;

/// The variants recorded for `key`, oldest first. Marks the key as recently used.
+ (NSArray<TrueImageVariant *> *)variantsForKey:(NSString *)key;

+ (void)recordURL:(NSString *)url pixelSize:(CGSize)pixelSize forKey:(NSString *)key;

/// Drops a variant a cache-only lookup could not find.
+ (void)forgetURL:(NSString *)url forKey:(NSString *)key;

#pragma mark - Testing

/// Writes any pending change now and waits for it.
+ (void)flush;
/// Forgets everything in memory and re-reads the file, as a new process would.
+ (void)reload;
/// Empties the index and deletes its file.
+ (void)reset;
@property (class, nonatomic, readonly) NSURL *fileURL;

@end

NS_ASSUME_NONNULL_END
