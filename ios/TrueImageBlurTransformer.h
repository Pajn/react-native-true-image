#import <UIKit/UIKit.h>

#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

/// Gaussian blur that first shrinks the image by `downscale`, then blurs the
/// small copy with a radius shrunk by the same factor. The blur erases every
/// detail finer than its radius, so the result looks the same as blurring the
/// original and costs a small fraction as much: a factor of f cuts the work
/// by about f cubed. Runs on SDWebImage's transform queue, never on the main
/// thread. The factor comes from TrueImageBlurDownscaleFactor.
@interface TrueImageBlurTransformer : NSObject <SDImageTransformer>

/// `blurRadius` is in source-image pixels. A `downscale` at or below 1 blurs
/// at full size.
+ (instancetype)transformerWithRadius:(CGFloat)blurRadius downscale:(CGFloat)downscale;

@property (nonatomic, assign, readonly) CGFloat blurRadius;
@property (nonatomic, assign, readonly) CGFloat downscale;

@end

NS_ASSUME_NONNULL_END
