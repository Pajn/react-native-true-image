#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Samples an image as a small square of RGBA bytes, which JS turns into a
/// palette. URLs load through TrueImageLoader at the sample size, so the
/// download and disk cache are shared with views and prefetches.
@interface TrueImagePixels : NSObject

/// Largest sample side accepted; JS asks for far less.
@property (class, nonatomic, readonly) NSUInteger maxSize;

/// The image stretched to `size` × `size` as row-major RGBA bytes, 8-bit and
/// not premultiplied, or nil if it could not be loaded or decoded. Scheme-less
/// sources name an asset catalog image. The completion runs on a background
/// queue.
+ (void)loadSource:(NSString *)source
           headers:(nullable NSDictionary<NSString *, NSString *> *)headers
              size:(NSUInteger)size
        completion:(void (^)(NSData *_Nullable rgba))completion;

/// Draws the image stretched over `size` × `size` and reads it back.
+ (nullable NSData *)rgbaFromImage:(UIImage *)image size:(NSUInteger)size;

@end

NS_ASSUME_NONNULL_END
