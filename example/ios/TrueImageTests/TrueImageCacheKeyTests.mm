#import "TrueImageTestCase.h"

#import <SDWebImage/SDWebImage.h>

#import "TrueImageVariants.h"

/// cacheKey: one picture at several URLs, and the index that remembers them.
@interface TrueImageCacheKeyTests : TrueImageTestCase
@end

@implementation TrueImageCacheKeyTests {
  NSString *_key;
  NSString *_small;
  NSString *_requested;
  NSString *_big;
  NSString *_thumb;
  /// The 40 pt test view in pixels.
  CGFloat _viewPixels;
}

- (void)setUp
{
  [super setUp];
  _key = @"album-1";
  _small = @"https://img.example.com/album-1?size=small";
  _requested = @"https://img.example.com/album-1?size=view";
  _big = @"https://img.example.com/album-1?size=big";
  _thumb = @"https://img.example.com/thumb.jpg";
  _viewPixels = 40 * UIScreen.mainScreen.scale;
  self.network.dataByURL[_small] = [TrueImageTestCase pngWithSize:CGSizeMake(8, 8) color:UIColor.greenColor];
  self.network.dataByURL[_requested] =
      [TrueImageTestCase pngWithSize:CGSizeMake(_viewPixels, _viewPixels) color:UIColor.redColor];
  self.network.dataByURL[_big] =
      [TrueImageTestCase pngWithSize:CGSizeMake(_viewPixels * 2, _viewPixels * 2) color:UIColor.blueColor];
  self.network.dataByURL[_thumb] = [TrueImageTestCase pngWithSize:CGSizeMake(16, 16) color:UIColor.yellowColor];
}

/// Prefetched at the test view's size, so the view's request is a memory hit.
- (void)prefetchVariant:(NSString *)url key:(NSString *)key
{
  NSMutableDictionary *request = [@{@"uri" : url, @"displayWidth" : @40, @"displayHeight" : @40} mutableCopy];
  request[@"cacheKey"] = key;
  XCTAssertTrue(([self prefetch:@[ request ]]));
}

- (TrueImageHarness *)sizedHarness
{
  TrueImageHarness *h = [self harness];
  h.view.downsampleThreshold = 2;
  return h;
}

- (void)setSource:(NSString *)source key:(NSString *)key on:(TrueImageHarness *)h transition:(NSInteger)transition
{
  h.view.cacheKey = key;
  [h setSource:source transition:transition recyclingKey:nil];
}

- (size_t)shownWidth:(TrueImageHarness *)h
{
  return CGImageGetWidth((CGImageRef)h.imageLayer.contents);
}

- (NSArray<NSString *> *)urlsForKey:(NSString *)key
{
  return [[TrueImageVariants variantsForKey:key] valueForKey:@"url"];
}

#pragma mark - Index

- (void)testPrefetchRecordsTheSourceSizeOfItsVariant
{
  XCTAssertTrue(([self prefetch:@[ @{@"uri" : _big, @"cacheKey" : _key, @"displayWidth" : @4, @"displayHeight" : @4} ]]));
  NSArray<TrueImageVariant *> *variants = [TrueImageVariants variantsForKey:_key];
  XCTAssertEqual(variants.count, 1u);
  XCTAssertEqualObjects(variants.firstObject.url, _big);
  XCTAssertEqual(variants.firstObject.pixelSize.width, _viewPixels * 2, @"the URL's size, not the reduced decode's");
}

- (void)testIndexSurvivesAProcessRestart
{
  [TrueImageVariants recordURL:_small pixelSize:CGSizeMake(80, 80) forKey:_key];
  [TrueImageVariants recordURL:_big pixelSize:CGSizeMake(512, 512) forKey:_key];
  [TrueImageVariants recordURL:_thumb pixelSize:CGSizeMake(256, 256) forKey:@"album-2"];
  [TrueImageVariants flush];
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:TrueImageVariants.fileURL.path]);
  [TrueImageVariants reload];
  XCTAssertEqualObjects([self urlsForKey:_key], (@[ _small, _big ]));
  XCTAssertEqual([TrueImageVariants variantsForKey:_key].lastObject.pixelSize.width, 512);
  XCTAssertEqualObjects([self urlsForKey:@"album-2"], @[ _thumb ]);
}

- (void)testKeysAreBoundedLeastRecentlyUsedFirstAcrossRestarts
{
  NSUInteger max = TrueImageVariants.maxKeys;
  for (NSUInteger i = 0; i < max; i++) {
    [TrueImageVariants recordURL:_small pixelSize:CGSizeMake(8, 8) forKey:[NSString stringWithFormat:@"k%lu", (unsigned long)i]];
  }
  // Reading k0 makes k1 the least recently used.
  [TrueImageVariants variantsForKey:@"k0"];
  [TrueImageVariants recordURL:_small pixelSize:CGSizeMake(8, 8) forKey:@"new"];
  XCTAssertEqual([TrueImageVariants variantsForKey:@"k0"].count, 1u);
  XCTAssertEqual([TrueImageVariants variantsForKey:@"k1"].count, 0u);
  [TrueImageVariants flush];
  [TrueImageVariants reload];
  XCTAssertEqual([TrueImageVariants variantsForKey:@"k0"].count, 1u);
  XCTAssertEqual([TrueImageVariants variantsForKey:@"k1"].count, 0u);
  XCTAssertEqual([TrueImageVariants variantsForKey:@"new"].count, 1u);
}

- (void)testVariantsPerKeyAreBounded
{
  NSUInteger max = TrueImageVariants.maxVariants;
  NSMutableArray *expected = [NSMutableArray new];
  for (NSUInteger i = 0; i < max + 2; i++) {
    NSString *url = [NSString stringWithFormat:@"%@&v=%lu", _small, (unsigned long)i];
    [TrueImageVariants recordURL:url pixelSize:CGSizeMake(8 + i, 8 + i) forKey:_key];
    if (i >= 2) [expected addObject:url];
  }
  XCTAssertEqualObjects([self urlsForKey:_key], expected);
}

- (void)testCorruptIndexFileStartsEmptyAndIsReplaced
{
  [[@"{\"version\":1,\"keys\":[{\"key\":" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:TrueImageVariants.fileURL
                                                                                     atomically:YES];
  [TrueImageVariants reload];
  XCTAssertEqual([TrueImageVariants variantsForKey:_key].count, 0u);
  [TrueImageVariants recordURL:_big pixelSize:CGSizeMake(512, 512) forKey:_key];
  [TrueImageVariants flush];
  [TrueImageVariants reload];
  XCTAssertEqualObjects([self urlsForKey:_key], @[ _big ]);
}

- (void)testChoiceSplitsSufficientSmallestFirstAndSmallerLargestFirst
{
  TrueImageVariant *v80 = [TrueImageVariant variantWithURL:@"u80" pixelSize:CGSizeMake(80, 80)];
  TrueImageVariant *v256 = [TrueImageVariant variantWithURL:@"u256" pixelSize:CGSizeMake(256, 256)];
  TrueImageVariant *v512 = [TrueImageVariant variantWithURL:@"u512" pixelSize:CGSizeMake(512, 512)];
  TrueImageVariant *v1024 = [TrueImageVariant variantWithURL:@"u1024" pixelSize:CGSizeMake(1024, 1024)];
  TrueImageVariantChoice *choice = [TrueImageVariants choose:@[ v1024, v80, v512, v256 ]
                                                   excluding:@"u512"
                                                  viewPixels:CGSizeMake(300, 300)
                                                     fitMode:TrueImageFitModeCover];
  XCTAssertEqualObjects(choice.sufficient, @[ v1024 ]);
  XCTAssertEqualObjects(choice.smaller, (@[ v256, v80 ]));
}

#pragma mark - View

- (void)testSufficientVariantInMemoryIsShownSynchronouslyWithoutFetching
{
  [self prefetchVariant:_big key:_key];
  TrueImageHarness *h = [self sizedHarness];
  [self setSource:_requested key:_key on:h transition:300];
  // Inside commit and without a fade, as an exact memory hit would be.
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertFalse(h.isFading);
  XCTAssertEqualObjects(h.payloads[0][@"source"], _requested, @"onLoad names the source the view asked for");
  XCTAssertEqualWithAccuracy([h.payloads[0][@"width"] doubleValue], _viewPixels * 2, 1,
                             @"and the size of the image actually shown");
  XCTAssertEqual([self.network fetchCount:_requested], 0u, @"the requested URL is never fetched");
  XCTAssertEqual([self.network fetchCount:_big], 1u);

  [h reset];
  [h.view commit];
  [self spin:0.1];
  XCTAssertEqual(h.events.count, 0u, @"committing again keeps the reused variant");
}

- (void)testSufficientVariantOnDiskIsDecodedWithoutTheNetwork
{
  [self prefetchVariant:_big key:_key];
  [SDImageCache.sharedImageCache clearMemory];
  TrueImageHarness *h = [self sizedHarness];
  [self setSource:_requested key:_key on:h transition:0];
  XCTAssertTrue([self waitFor:^{
    return h.events.count >= 3;
  }]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertEqual([self.network fetchCount:_requested], 0u);
  XCTAssertEqual([self.network fetchCount:_big], 1u);
}

- (void)testSmallerVariantStandsInUntilTheImageArrivesThenCrossfades
{
  [self prefetchVariant:_small key:_key];
  [self.network.hang addObject:_requested];
  TrueImageHarness *h = [self sizedHarness];
  h.view.placeholderTransition = 200;
  [self setSource:_requested key:_key on:h transition:300];
  XCTAssertEqual([self shownWidth:h], 8u, @"a memory-cached variant shows inside commit");
  XCTAssertEqual(h.events.count, 0u, @"a stand-in reports nothing");
  XCTAssertTrue([self waitFor:^{
    return [self.network fetchCount:self->_requested] == 1;
  }]);
  [self.network release:_requested];
  XCTAssertTrue([self waitFor:^{
    return h.events.count >= 2;
  }]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display" ]));
  CABasicAnimation *fade = (CABasicAnimation *)[h.imageLayer animationForKey:@"fade"];
  XCTAssertEqualObjects(fade.keyPath, @"contents", @"leaving the stand-in crossfades");
  XCTAssertEqualWithAccuracy(fade.duration, 0.2, 0.001);
  XCTAssertTrue([self waitFor:^{
    return h.events.count >= 3;
  }]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertEqualObjects([self urlsForKey:_key], (@[ _small, _requested ]));
}

- (void)testEvictedVariantIsForgottenAndTheSourceIsFetched
{
  // Recorded by an earlier process; the caches no longer have it.
  [TrueImageVariants recordURL:_big pixelSize:CGSizeMake(_viewPixels * 2, _viewPixels * 2) forKey:_key];
  TrueImageHarness *h = [self sizedHarness];
  [self setSource:_requested key:_key on:h transition:0];
  XCTAssertTrue([self waitFor:^{
    return h.events.count >= 3;
  }]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertEqual([self.network fetchCount:_requested], 1u);
  XCTAssertEqual([self.network fetchCount:_big], 0u, @"a cache-only lookup never fetches");
  XCTAssertEqualObjects([self urlsForKey:_key], @[ _requested ]);
}

- (void)testExactURLInMemoryWinsOverAVariant
{
  [self prefetchVariant:_big key:_key];
  [self prefetchVariant:_requested key:_key];
  TrueImageHarness *h = [self sizedHarness];
  [self setSource:_requested key:_key on:h transition:0];
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertEqualWithAccuracy([h.payloads[0][@"width"] doubleValue], _viewPixels, 1);
}

- (void)testWithoutACacheKeyNothingChanges
{
  [self prefetchVariant:_big key:_key];
  [self prefetchVariant:_small key:_key];
  [self.network.hang addObject:_requested];
  TrueImageHarness *h = [self sizedHarness];
  [self setSource:_requested key:nil on:h transition:0];
  XCTAssertNil(h.imageLayer.contents, @"no stand-in without a cache key");
  XCTAssertTrue([self waitFor:^{
    return [self.network fetchCount:self->_requested] == 1;
  }]);
  [self.network release:_requested];
  XCTAssertTrue([self waitFor:^{
    return h.events.count >= 3;
  }]);
  XCTAssertEqualWithAccuracy([h.payloads[0][@"width"] doubleValue], _viewPixels, 1);
}

- (void)testSameKeyVariantBeatsACacheOnlyPlaceholder
{
  [self prefetchVariant:_small key:_key];
  XCTAssertTrue(([self prefetch:@[ @{@"uri" : _thumb, @"displayWidth" : @40, @"displayHeight" : @40} ]]));
  [self.network.hang addObject:_requested];
  TrueImageHarness *h = [self sizedHarness];
  h.view.placeholder = _thumb;
  [self setSource:_requested key:_key on:h transition:0];
  XCTAssertEqual([self shownWidth:h], 8u, @"the same picture, not the explicit placeholder");

  TrueImageHarness *network = [self sizedHarness];
  network.view.placeholder = _thumb;
  network.view.placeholderFromNetwork = YES;
  [self setSource:_requested key:_key on:network transition:0];
  XCTAssertTrue([self waitFor:^{
    return network.imageLayer.contents != nil;
  }]);
  XCTAssertEqual([self shownWidth:network], 16u, @"a network placeholder is the app's choice and wins");
}

- (void)testRecycledRowReusesAVariantWithoutCrossfadingThePreviousItem
{
  NSString *otherRequested = @"https://img.example.com/album-2?size=view";
  NSString *otherBig = @"https://img.example.com/album-2?size=big";
  self.network.dataByURL[otherBig] = self.network.dataByURL[_big];
  [self prefetchVariant:_big key:_key];
  [self prefetchVariant:otherBig key:@"album-2"];
  TrueImageHarness *h = [self sizedHarness];
  h.view.cacheKey = _key;
  [h setSource:_requested transition:300 recyclingKey:@"1"];
  [h reset];
  h.view.cacheKey = @"album-2";
  [h setSource:otherRequested transition:300 recyclingKey:@"2"];
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertFalse(h.isFading);
  XCTAssertEqual([self.network fetchCount:otherRequested], 0u);
}

@end
