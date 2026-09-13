#import "TrueImageTestCase.h"

#import <SDWebImage/SDWebImage.h>

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

@end
