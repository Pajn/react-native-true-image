#import "TrueImageTestCase.h"

#import <SDWebImage/SDWebImage.h>

#import "TrueImageModule.h"

/// The prefetch/view cache-key contract.
@interface TrueImagePrefetchParityTests : TrueImageTestCase
@end

@implementation TrueImagePrefetchParityTests {
  NSString *_url;
}

- (void)setUp
{
  [super setUp];
  _url = @"https://cdn.example.com/cover.jpg";
}

- (void)testPrefetchedURLIsASynchronousMemoryHitInTheView
{
  XCTAssertTrue(([self prefetch:@[ _url ]]));
  TrueImageHarness *h = [self harness];
  [h setSource:_url transition:300 recyclingKey:nil];
  // Delivered inside commit: no run loop spin, and no fade because a
  // cached image in an empty view is not late.
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertNotNil(h.imageLayer.contents);
  XCTAssertFalse(h.isFading);
  XCTAssertEqual([self.network fetchCount:_url], 1u);
}

- (void)testImageIsFetchedExactlyOnceAcrossPrefetchAndView
{
  [self prefetch:@[ _url ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_url transition:0 recyclingKey:nil];
  [self spin:0.1];
  XCTAssertEqual([self.network fetchCount:_url], 1u);
}

- (void)testFailedPrefetchDoesNotBlacklistTheURL
{
  [self.network.failOnce addObject:_url];
  XCTAssertFalse(([self prefetch:@[ _url ]]));
  TrueImageHarness *h = [self harness];
  [h setSource:_url transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitFor:^{
    return h.events.count >= 3;
  }]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertEqual([self.network fetchCount:_url], 2u);
}

- (void)testBlurredLoadReusesThePrefetchedSharpOriginal
{
  [self prefetch:@[ _url ]];
  TrueImageHarness *h = [self harness];
  h.view.blurRadius = 4;
  [h setSource:_url transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitFor:^{
    return h.events.count >= 3;
  }]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertEqual([self.network fetchCount:_url], 1u, @"the blur is transformed from the cached original");

  // The transformed image has its own cache entry: a second blurred view is a memory hit.
  TrueImageHarness *second = [self harness];
  second.view.blurRadius = 4;
  [second setSource:_url transition:300 recyclingKey:nil];
  XCTAssertEqualObjects(second.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertFalse(second.isFading);
}

- (void)testEmptyListResolvesTrue
{
  XCTAssertTrue(([self prefetch:@[]]));
}

- (void)testPartialFailureResolvesFalseAndAllSuccessTrue
{
  NSString *bad = @"https://cdn.example.com/bad.jpg";
  [self.network.failAlways addObject:bad];
  XCTAssertFalse(([self prefetch:@[ _url, bad ]]));
  XCTAssertTrue(([self prefetch:@[ _url, @"https://cdn.example.com/ok.jpg" ]]));
}

- (void)testUnparseableSourceInTheListForcesFalse
{
  XCTAssertFalse(([self prefetch:@[ _url, @"ic_play" ]]));
  XCTAssertEqual([self.network fetchCount:_url], 1u, @"the valid URL is still prefetched");
}

- (void)testHeadersAreSentButKeptOutOfTheCacheKey
{
  NSDictionary *headers = @{@"Authorization" : @"Bearer t", @"X-Proxy" : @"shelf"};
  XCTAssertTrue(([self prefetch:@[ @{@"uri" : _url, @"headers" : headers} ]]));
  XCTAssertEqualObjects(self.network.headersSeen[_url], headers);

  // A view that names the same URL without headers still gets the memory hit.
  TrueImageHarness *h = [self harness];
  [h setSource:_url transition:300 recyclingKey:nil];
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertEqual([self.network fetchCount:_url], 1u);
}

- (void)testViewSendsItsHeaders
{
  TrueImageHarness *h = [self harness];
  h.view.headers = @{@"Authorization" : @"Bearer v"};
  [h setSource:_url transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitFor:^{
    return h.events.count >= 3;
  }]);
  XCTAssertEqualObjects(self.network.headersSeen[_url], @{@"Authorization" : @"Bearer v"});
}

- (void)testModuleTreatsMalformedEntriesAsFailuresButStillLoadsTheRest
{
  __block NSNumber *result;
  TrueImageModule *module = [TrueImageModule new];
  [module prefetch:@[ @"junk", @{}, @{@"uri" : @42}, @{@"uri" : _url} ]
           resolve:^(id value) {
             result = value;
           }
            reject:^(NSString *code, NSString *message, NSError *error) {
              XCTFail(@"must resolve");
            }];
  XCTAssertTrue([self waitFor:^{
    return result != nil;
  }]);
  XCTAssertFalse(result.boolValue);
  XCTAssertEqual([self.network fetchCount:_url], 1u);
}

- (void)testWebPDecodes
{
  // A 1x1 lossless WebP.
  NSData *webp = [[NSData alloc] initWithBase64EncodedString:@"UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA=="
                                                     options:0];
  XCTAssertNotNil(webp);
  XCTAssertEqual([NSData sd_imageFormatForImageData:webp], SDImageFormatWebP);
  UIImage *image = [SDImageCodersManager.sharedManager decodedImageWithData:webp options:nil];
  XCTAssertNotNil(image, @"the WebP coder is registered by configureOnce");
  XCTAssertEqual(image.size.width, 1);
  XCTAssertEqual(image.size.height, 1);
}


- (void)testSizedPrefetchDownsamplesAndMatchesViewSynchronously
{
  self.network.defaultData = [TrueImageTestCase pngWithSize:CGSizeMake(1200, 600) color:UIColor.redColor];
  XCTAssertTrue(([self prefetch:@[@{@"uri": _url, @"displayWidth": @40, @"displayHeight": @40}]]));
  TrueImageHarness *h = [self harness];
  h.view.downsampleThreshold = 2;
  [h setSource:_url transition:300 recyclingKey:nil];
  XCTAssertEqualObjects(h.events, (@[@"load", @"display", @"displayEnd"]));
  CGFloat scale = h.view.traitCollection.displayScale;
  XCTAssertEqualWithAccuracy([h.payloads.firstObject[@"width"] doubleValue], 80 * scale, 1);
  XCTAssertEqualWithAccuracy([h.payloads.firstObject[@"height"] doubleValue], 40 * scale, 1);
  XCTAssertFalse(h.isFading);
  XCTAssertEqual([self.network fetchCount:_url], 1u);

  // A larger view must not inherit the reduced variant; raw data is shared.
  h.view.frame = CGRectMake(0, 0, 400, 400);
  [h.view setNeedsLayout];
  [h.view layoutIfNeeded];
  XCTAssertTrue([self waitFor:^{ return [h.payloads.lastObject[@"width"] doubleValue] == 1200; }]);
  XCTAssertEqual([self.network fetchCount:_url], 1u);
}

- (void)testDefaultSizingWaitsForLayoutAndOptOutKeepsOriginal
{
  self.network.defaultData = [TrueImageTestCase pngWithSize:CGSizeMake(1200, 1200) color:UIColor.redColor];
  TrueImageHarness *h = [self harnessWithFrame:CGRectZero];
  h.view.downsampleThreshold = 2;
  [h setSource:_url transition:0 recyclingKey:nil];
  [self spin:0.05];
  XCTAssertEqual([self.network fetchCount:_url], 0u);
  h.view.frame = CGRectMake(0, 0, 40, 40);
  [h.view setNeedsLayout];
  [h.view layoutIfNeeded];
  XCTAssertTrue([self waitFor:^{ return h.events.count >= 3; }]);
  XCTAssertLessThan([h.payloads.lastObject[@"width"] doubleValue], 1200);
  h.view.downsampleThreshold = 0;
  [h.view commit];
  XCTAssertTrue([self waitFor:^{ return [h.payloads.lastObject[@"width"] doubleValue] == 1200; }]);
}


- (void)testRoughPrefetchDimensionsReuseAdequateVariant
{
  self.network.defaultData = [TrueImageTestCase pngWithSize:CGSizeMake(1200, 1200) color:UIColor.redColor];
  XCTAssertTrue(([self prefetch:@[@{@"uri": _url, @"displayWidth": @50, @"displayHeight": @50}]]));
  TrueImageHarness *h = [self harness]; // 40pt view uses the 50pt decode.
  h.view.downsampleThreshold = 2;
  [h setSource:_url transition:300 recyclingKey:nil];
  XCTAssertEqualObjects(h.events, (@[@"load", @"display", @"displayEnd"]));
  CGFloat pixels = 50 * h.view.traitCollection.displayScale;
  XCTAssertEqualWithAccuracy([h.payloads.firstObject[@"width"] doubleValue], pixels, 1);
  h.view.frame = CGRectMake(0, 0, 20, 20); // 50/20 > 2, so decode a smaller variant.
  [h.view setNeedsLayout]; [h.view layoutIfNeeded];
  XCTAssertTrue([self waitFor:^{ return [h.payloads.lastObject[@"width"] doubleValue] < pixels; }]);
  XCTAssertEqual([self.network fetchCount:_url], 1u);
}


- (void)testRoughEstimateReusesOriginalUntilThresholdIsExceeded
{
  CGFloat scale = UIScreen.mainScreen.scale;
  CGFloat originalPixels = 80 * scale;
  self.network.defaultData = [TrueImageTestCase pngWithSize:CGSizeMake(originalPixels, originalPixels) color:UIColor.redColor];
  XCTAssertTrue(([self prefetch:@[@{@"uri": _url, @"displayWidth": @50, @"displayHeight": @50}]]));
  TrueImageHarness *h = [self harness];
  h.view.downsampleThreshold = 2;
  [h setSource:_url transition:300 recyclingKey:nil];
  XCTAssertEqualObjects(h.events, (@[@"load", @"display", @"displayEnd"]));
  XCTAssertEqual([h.payloads.firstObject[@"width"] doubleValue], originalPixels);
  h.view.frame = CGRectMake(0, 0, 30, 30);
  [h.view setNeedsLayout]; [h.view layoutIfNeeded];
  XCTAssertTrue([self waitFor:^{ return [h.payloads.lastObject[@"width"] doubleValue] < originalPixels; }]);
  XCTAssertEqual([self.network fetchCount:_url], 1u);
}

@end
