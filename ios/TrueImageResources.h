#import <UIKit/UIKit.h>

#import "TrueImagePolicy.h"

NS_ASSUME_NONNULL_BEGIN

/// Scheme-less sources name an asset catalog image. They are rasterised at
/// the view's size on the main thread, tinted, and drawn in the same frame.
@interface TrueImageResources : NSObject

+ (nullable UIImage *)imageNamed:(NSString *)name traits:(UITraitCollection *)traits;

/// Returns nil for a zero size. `pixelSize` receives the catalog image's
/// intrinsic size in pixels, reported through onLoad.
+ (nullable CGImageRef)rasterize:(UIImage *)image
                            size:(CGSize)size
                           scale:(CGFloat)scale
                            tint:(nullable UIColor *)tint
                            mode:(TrueImageFitMode)mode
                          traits:(UITraitCollection *)traits
                       pixelSize:(CGSize *)pixelSize CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
