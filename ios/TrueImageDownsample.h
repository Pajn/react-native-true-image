#import <SDWebImage/SDWebImage.h>
#import "TrueImagePolicy.h"

/// Request-local coder and transformer. Dimensions are read before bitmap allocation.
@interface TrueImageDownsample : NSObject <SDImageCoder, SDImageTransformer>
@property (nonatomic) CGSize pixelSize;
@property (nonatomic, readonly) CGSize originalPixels;
@property (nonatomic, readonly) CGSize decodedPixels;
@property (nonatomic) TrueImageFitMode fitMode;
@property (nonatomic) CGFloat threshold;
@property (nonatomic) CGFloat blurRadius;
@property (nonatomic) CGFloat blurDownscale;
@end
