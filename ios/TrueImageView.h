#import <UIKit/UIKit.h>

#import "TrueImagePolicy.h"

NS_ASSUME_NONNULL_BEGIN

/// One view, one layer, one image. No subviews and no placeholder views:
/// that is the performance premise of the whole module. Props are set by
/// the Fabric component view and applied together in `commit`.
@interface TrueImageView : UIView

#pragma mark - Props

@property (nonatomic, copy, nullable) NSString *source;
/// Sent with remote requests. Not part of the cache key.
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, assign) TrueImageFitMode fitMode;
/// Fade duration in milliseconds.
@property (nonatomic, assign) NSInteger transition;
/// In source-image pixels.
@property (nonatomic, assign) CGFloat blurRadius;
/// How many pixels the blur radius spans after the pre-blur shrink.
/// Defaults to TrueImageDefaultBlurPixelsPerRadius; 0 blurs at full size.
@property (nonatomic, assign) CGFloat blurPixelsPerRadius;
@property (nonatomic, strong, nullable) UIColor *tint;
@property (nonatomic, copy, nullable) NSString *recyclingKey;
/// Shown into an empty view until `source` loads; the same shapes as
/// `source`. Never fades in and reports no events.
@property (nonatomic, copy, nullable) NSString *placeholder;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *placeholderHeaders;
/// Crossfade from the placeholder to the image, in milliseconds. 0 cuts.
@property (nonatomic, assign) NSInteger placeholderTransition;
/// Whether a remote placeholder may be fetched. Off, it shows only when
/// already cached.
@property (nonatomic, assign) BOOL placeholderFromNetwork;

#pragma mark - Events

/// (pixel width, pixel height, source)
@property (nonatomic, copy, nullable) void (^onLoad)(CGFloat width, CGFloat height, NSString *source);
/// (message, source)
@property (nonatomic, copy, nullable) void (^onError)(NSString *message, NSString *source);
@property (nonatomic, copy, nullable) void (^onDisplay)(void);
@property (nonatomic, copy, nullable) void (^onDisplayEnd)(void);

#pragma mark - Fabric entry points

/// Applies every prop set since the last commit. Runs inside the mount
/// transaction, so a recycling key change clears the layer before the new
/// source loads and the two never crossfade into each other.
- (void)commit;

/// Fabric reuses component views for unrelated components.
- (void)prepareForRecycle;

@end

NS_ASSUME_NONNULL_END
