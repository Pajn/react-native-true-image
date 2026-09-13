#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Resamples a decoded image once to the size it is actually drawn at when
/// the source is more than twice as large, so a 1200 px cover in a 60 pt
/// row does not cost the GPU a full-size texture every frame.
@interface TrueImageThumbnails : NSObject

@property (class, nonatomic, readonly) TrueImageThumbnails *shared;

- (nullable CGImageRef)cachedForKey:(NSString *)key CF_RETURNS_NOT_RETAINED;

/// Renders off the main thread and calls back on it. A cached thumbnail is
/// delivered synchronously.
- (void)makeFromImage:(UIImage *)image
            pixelSize:(CGSize)pixelSize
                  key:(NSString *)key
           completion:(void (^)(CGImageRef _Nullable thumbnail))completion;

@end

NS_ASSUME_NONNULL_END
