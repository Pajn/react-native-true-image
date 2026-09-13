#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "TrueImageFakeLoader.h"
#import "TrueImageLoader.h"
#import "TrueImageView.h"

NS_ASSUME_NONNULL_BEGIN

/// Records a view's events in order.
@interface TrueImageHarness : NSObject
@property (nonatomic, strong, readonly) TrueImageView *view;
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *events;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *payloads;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)setSource:(nullable NSString *)source transition:(NSInteger)transition recyclingKey:(nullable NSString *)key;
- (CALayer *)imageLayer;
- (BOOL)isFading;
- (void)reset;
@end

@interface TrueImageTestCase : XCTestCase
@property (nonatomic, strong, readonly) TrueImageFakeLoader *network;
@property (nonatomic, strong, readonly) UIWindow *window;

/// Spins the main run loop until `condition` holds or the timeout passes.
- (BOOL)waitFor:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout;
- (BOOL)waitFor:(BOOL (^)(void))condition;
- (void)spin:(NSTimeInterval)seconds;

/// Elements are URL strings or `@{ @"uri": …, @"headers": @{…} }` dictionaries.
- (BOOL)prefetch:(NSArray *)sources;
- (TrueImageHarness *)harness;
- (TrueImageHarness *)harnessWithFrame:(CGRect)frame;

+ (NSData *)pngWithSize:(CGSize)size color:(UIColor *)color;
+ (UIColor *)centerColorOf:(CGImageRef)image;

@end

NS_ASSUME_NONNULL_END
