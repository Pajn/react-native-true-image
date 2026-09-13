#import "TrueImageTestCase.h"

#import <SDWebImage/SDWebImage.h>

#import "TrueImageModule.h"

@implementation TrueImageHarness

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super init]) {
    _view = [[TrueImageView alloc] initWithFrame:frame];
    _events = [NSMutableArray new];
    _payloads = [NSMutableArray new];
    __weak __typeof(self) weakSelf = self;
    _view.onLoad = ^(CGFloat width, CGFloat height, NSString *source) {
      [weakSelf.events addObject:@"load"];
      [weakSelf.payloads addObject:@{@"width" : @(width), @"height" : @(height), @"source" : source}];
    };
    _view.onError = ^(NSString *message, NSString *source) {
      [weakSelf.events addObject:@"error"];
      [weakSelf.payloads addObject:@{@"error" : message, @"source" : source}];
    };
    _view.onDisplay = ^{
      [weakSelf.events addObject:@"display"];
    };
    _view.onDisplayEnd = ^{
      [weakSelf.events addObject:@"displayEnd"];
    };
  }
  return self;
}

- (void)setSource:(NSString *)source transition:(NSInteger)transition recyclingKey:(NSString *)key
{
  _view.source = source;
  _view.transition = transition;
  if (key) {
    _view.recyclingKey = key;
  }
  [_view commit];
}

- (CALayer *)imageLayer
{
  return _view.layer.sublayers.firstObject;
}

- (BOOL)isFading
{
  return [self.imageLayer animationForKey:@"fade"] != nil;
}

- (void)reset
{
  [_events removeAllObjects];
  [_payloads removeAllObjects];
}

@end

@implementation TrueImageTestCase

- (void)setUp
{
  [super setUp];
  self.continueAfterFailure = NO;
  [TrueImageLoader configureOnce];
  _network = [TrueImageFakeLoader new];
  _network.defaultData = [TrueImageTestCase pngWithSize:CGSizeMake(8, 8)
                                                  color:[UIColor colorWithRed:200 / 255.0 green:50 / 255.0 blue:50 / 255.0 alpha:1]];
  [TrueImageLoader setImageLoaderForTesting:_network];

  SDImageCache *cache = SDImageCache.sharedImageCache;
  [cache clearMemory];
  XCTestExpectation *cleared = [self expectationWithDescription:@"disk cleared"];
  [cache clearDiskOnCompletion:^{
    [cleared fulfill];
  }];
  [self waitForExpectations:@[ cleared ] timeout:5];

  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:UIWindowScene.class]) {
      _window = ((UIWindowScene *)scene).windows.firstObject;
      break;
    }
  }
  if (!_window) {
    _window = UIApplication.sharedApplication.windows.firstObject;
  }
  XCTAssertNotNil(_window, @"hosted tests need the app window for layer animations");
}

- (void)tearDown
{
  [TrueImageLoader setImageLoaderForTesting:nil];
  for (UIView *subview in [_window.subviews copy]) {
    if ([subview isKindOfClass:TrueImageView.class]) {
      [subview removeFromSuperview];
    }
  }
  [super tearDown];
}

- (BOOL)waitFor:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout
{
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (!condition()) {
    if ([deadline timeIntervalSinceNow] < 0) {
      return NO;
    }
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  return YES;
}

- (BOOL)waitFor:(BOOL (^)(void))condition
{
  return [self waitFor:condition timeout:5];
}

- (void)spin:(NSTimeInterval)seconds
{
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([deadline timeIntervalSinceNow] > 0) {
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
}

/// Goes through the module so URL parsing is exercised too.
- (BOOL)prefetch:(NSArray *)sources
{
  NSMutableArray *requests = [NSMutableArray arrayWithCapacity:sources.count];
  for (id source in sources) {
    if ([source isKindOfClass:NSString.class]) {
      [requests addObject:@{@"uri" : source}];
      continue;
    }
    NSDictionary *dictionary = source;
    NSMutableArray *headers = [NSMutableArray new];
    [dictionary[@"headers"] enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
      [headers addObject:@{@"name" : name, @"value" : value}];
    }];
    [requests addObject:@{@"uri" : dictionary[@"uri"], @"headers" : headers}];
  }
  __block NSNumber *result;
  TrueImageModule *module = [TrueImageModule new];
  [module prefetch:requests
           resolve:^(id value) {
             result = value;
           }
            reject:^(NSString *code, NSString *message, NSError *error) {
              XCTFail(@"prefetch rejected: %@", message);
            }];
  XCTAssertTrue([self waitFor:^{
    return result != nil;
  }], @"prefetch did not complete");
  return result.boolValue;
}

- (TrueImageHarness *)harness
{
  return [self harnessWithFrame:CGRectMake(0, 0, 40, 40)];
}

- (TrueImageHarness *)harnessWithFrame:(CGRect)frame
{
  TrueImageHarness *harness = [[TrueImageHarness alloc] initWithFrame:frame];
  [_window addSubview:harness.view];
  [harness.view layoutIfNeeded];
  return harness;
}

+ (NSData *)pngWithSize:(CGSize)size color:(UIColor *)color
{
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
  format.scale = 1;
  format.opaque = YES;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
  return [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
    [color setFill];
    [context fillRect:CGRectMake(0, 0, size.width, size.height)];
  }];
}

+ (UIColor *)centerColorOf:(CGImageRef)image
{
  size_t width = CGImageGetWidth(image);
  size_t height = CGImageGetHeight(image);
  uint8_t pixel[4] = {0, 0, 0, 0};
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(
      pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  // Draw the image so its centre pixel lands on the single output pixel.
  CGContextDrawImage(context, CGRectMake(-(CGFloat)width / 2 + 0.5, -(CGFloat)height / 2 + 0.5, width, height), image);
  CGContextRelease(context);
  CGColorSpaceRelease(space);
  CGFloat alpha = pixel[3] / 255.0;
  if (alpha == 0) {
    return UIColor.clearColor;
  }
  return [UIColor colorWithRed:pixel[0] / 255.0 / alpha green:pixel[1] / 255.0 / alpha blue:pixel[2] / 255.0 / alpha alpha:alpha];
}

@end
