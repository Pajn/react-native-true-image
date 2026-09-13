#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

/// WebP decoding through ImageIO, which Apple has supported since iOS 14.
/// SDWebImage leaves WebP off by default. This mirrors SDWebImage's own
/// Apple WebP coder without adding a dependency.
@interface TrueImageWebPCoder : SDImageIOAnimatedCoder <SDProgressiveImageCoder, SDAnimatedImageCoder>

@property (nonatomic, class, readonly) TrueImageWebPCoder *sharedCoder;

@end

NS_ASSUME_NONNULL_END
