#import "TrueImageTestCase.h"

/// Native view behaviour: fades, events, clearing, catalog images.
@interface TrueImageViewTests : TrueImageTestCase
@end

@implementation TrueImageViewTests {
  NSString *_a;
  NSString *_b;
}

- (void)setUp
{
  [super setUp];
  _a = @"https://cdn.example.com/a.jpg";
  _b = @"https://cdn.example.com/b.jpg";
}

- (BOOL)waitForEvents:(TrueImageHarness *)h count:(NSUInteger)count
{
  return [self waitFor:^{
    return h.events.count >= count;
  }];
}

- (void)testRecycledViewWithCachedImageDrawsAtOnceWithoutFade
{
  [self prefetch:@[ _a, _b ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:300 recyclingKey:@"1"];
  [h reset];
  [h setSource:_b transition:300 recyclingKey:@"2"];
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertFalse(h.isFading);
}

- (void)testNoFadePathEmitsAllThreeEventsInOneFrame
{
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:3]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertEqualObjects(h.payloads[0][@"width"], @8, @"onLoad reports pixel size");
  XCTAssertEqualObjects(h.payloads[0][@"source"], _a);
  XCTAssertFalse(h.isFading);
}

- (void)testFadePathEmitsDisplayEndOnlyWhenTheFadeEnds
{
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:200 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:2]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display" ]));
  CABasicAnimation *fade = (CABasicAnimation *)[h.imageLayer animationForKey:@"fade"];
  XCTAssertNotNil(fade);
  XCTAssertEqualObjects(fade.keyPath, @"opacity", @"an empty layer fades its opacity");
  XCTAssertEqualWithAccuracy(fade.duration, 0.2, 0.001);
  XCTAssertTrue([self waitForEvents:h count:3]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
}

- (void)testReplacingADisplayedImageCrossfadesContents
{
  [self prefetch:@[ _a, _b ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:200 recyclingKey:nil];
  [h reset];
  [h setSource:_b transition:200 recyclingKey:nil];
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display" ]), @"a replacement always crossfades, even from memory");
  CABasicAnimation *fade = (CABasicAnimation *)[h.imageLayer animationForKey:@"fade"];
  XCTAssertEqualObjects(fade.keyPath, @"contents");
  XCTAssertTrue([self waitForEvents:h count:3]);
}

- (void)testInterruptedFadeReportsDisplayEndOnlyForTheImageStillShown
{
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:300 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:2]);
  [self spin:0.1];
  [h setSource:_b transition:300 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:4]);
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"load", @"display" ]));
  [self spin:0.6];
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"load", @"display", @"displayEnd" ]));
}

- (void)testInterruptedFadeInResumesFromItsCurrentOpacity
{
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:400 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:2]);
  [self spin:0.2];
  [h setSource:_b transition:400 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:4]);
  CABasicAnimation *fade = (CABasicAnimation *)[h.imageLayer animationForKey:@"fade"];
  XCTAssertEqualObjects(fade.keyPath, @"opacity", @"a running fade-in keeps fading opacity instead of crossfading");
  XCTAssertGreaterThan([fade.fromValue floatValue], 0.2, @"it carries on from where it was, not from zero");
  XCTAssertLessThan([fade.fromValue floatValue], 0.9);
  [self spin:0.6];
  NSUInteger ends = [h.events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'displayEnd'"]].count;
  XCTAssertEqual(ends, 1u);
}

- (void)testReplacementInterruptedByAnotherReplacementReportsOnce
{
  NSString *c = @"https://cdn.example.com/c.jpg";
  [self prefetch:@[ _a, _b, c ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:300 recyclingKey:nil];
  [h setSource:_b transition:300 recyclingKey:nil];
  [self spin:0.1];
  [h setSource:c transition:300 recyclingKey:nil];
  [h reset];
  CABasicAnimation *fade = (CABasicAnimation *)[h.imageLayer animationForKey:@"fade"];
  XCTAssertEqualObjects(fade.keyPath, @"contents");
  [self spin:0.5];
  XCTAssertEqualObjects(h.events, @[ @"displayEnd" ]);
  XCTAssertFalse(h.isFading);
}

- (void)testCommittingTheSameSourceAgainDoesNotReload
{
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:3]);
  [h setSource:_a transition:0 recyclingKey:nil];
  [h.view commit];
  [self spin:0.1];
  XCTAssertEqual([self.network fetchCount:_a], 1u);
  XCTAssertEqual(h.events.count, 3u);
}

- (void)testReapplyingTheSameRecyclingKeyDoesNotClear
{
  [self prefetch:@[ _a ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:@"1"];
  [h reset];
  [h setSource:_a transition:0 recyclingKey:@"1"];
  XCTAssertNotNil(h.imageLayer.contents);
  XCTAssertEqual(h.events.count, 0u);
}

- (void)testBlurChangeTransformsTheCachedOriginalWithoutRefetching
{
  [self prefetch:@[ _a ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  [h reset];
  h.view.blurRadius = 6;
  [h.view commit];
  XCTAssertTrue([self waitForEvents:h count:3], @"a new blur is a new image and reports as one");
  XCTAssertEqual([self.network fetchCount:_a], 1u);
}

- (void)testLargeBlurShrinksTheImageBeforeBlurring
{
  self.network.dataByURL[_a] = [TrueImageTestCase pngWithSize:CGSizeMake(1000, 1000) color:UIColor.greenColor];
  TrueImageHarness *h = [self harness];
  h.view.blurRadius = 100;
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:3]);
  // 1000 px shrunk by 100 / 2 = 50 is 20 px; far below the view, so the thumbnail tier leaves it alone.
  XCTAssertEqual(CGImageGetWidth((CGImageRef)h.imageLayer.contents), 20u);
  XCTAssertEqualObjects([TrueImageTestCase centerColorOf:(CGImageRef)h.imageLayer.contents], UIColor.greenColor,
                        @"a flat image blurs to itself");
}

- (void)testMorePixelsPerRadiusKeepsAFinerBlur
{
  self.network.dataByURL[_a] = [TrueImageTestCase pngWithSize:CGSizeMake(1000, 1000) color:UIColor.greenColor];
  TrueImageHarness *h = [self harness];
  h.view.blurRadius = 100;
  h.view.blurPixelsPerRadius = 10;
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:3]);
  XCTAssertEqual(CGImageGetWidth((CGImageRef)h.imageLayer.contents), 100u);
}

- (void)testZeroPixelsPerRadiusBlursAtFullSize
{
  self.network.dataByURL[_a] = [TrueImageTestCase pngWithSize:CGSizeMake(1000, 1000) color:UIColor.greenColor];
  TrueImageHarness *h = [self harness];
  h.view.blurRadius = 100;
  h.view.blurPixelsPerRadius = 0;
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:3]);
  CGFloat scale = h.view.traitCollection.displayScale;
  XCTAssertTrue([self waitFor:^{
    // The full-size blur is what the thumbnail tier resamples down to the view.
    return CGImageGetWidth((CGImageRef)h.imageLayer.contents) == (size_t)(40 * scale);
  }]);
}

- (void)testPixelsPerRadiusChangeIsANewImage
{
  [self prefetch:@[ _a ]];
  TrueImageHarness *h = [self harness];
  h.view.blurRadius = 6;
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:3]);
  [h reset];
  h.view.blurPixelsPerRadius = 4;
  [h.view commit];
  XCTAssertTrue([self waitForEvents:h count:3], @"a different shrink is a different image and reports as one");
  XCTAssertEqual([self.network fetchCount:_a], 1u);
}

- (void)testPixelsPerRadiusChangeWithoutABlurIsNotANewImage
{
  [self prefetch:@[ _a ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  [h reset];
  h.view.blurPixelsPerRadius = 4;
  [h.view commit];
  [self spin:0.1];
  XCTAssertEqual(h.events.count, 0u, @"the shrink factor is 1 either way, so nothing reloads");
}

- (void)testResizeRefinesToALargerThumbnail
{
  self.network.dataByURL[_a] = [TrueImageTestCase pngWithSize:CGSizeMake(1000, 1000) color:UIColor.greenColor];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:3]);
  CGFloat scale = h.view.traitCollection.displayScale;
  XCTAssertTrue([self waitFor:^{
    return CGImageGetWidth((CGImageRef)h.imageLayer.contents) == (size_t)(40 * scale);
  }]);
  h.view.frame = CGRectMake(0, 0, 100, 100);
  [h.view layoutIfNeeded];
  XCTAssertTrue([self waitFor:^{
    return CGImageGetWidth((CGImageRef)h.imageLayer.contents) == (size_t)(100 * scale);
  }], @"a bigger view gets a bigger thumbnail");
  XCTAssertEqual(h.events.count, 3u);
}

- (void)testNullSourceClearsAndEmitsNothing
{
  [self prefetch:@[ _a ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  [h reset];
  [h setSource:nil transition:0 recyclingKey:nil];
  XCTAssertNil(h.imageLayer.contents);
  XCTAssertEqual(h.events.count, 0u);
}

- (void)testRecyclingKeyChangeClearsSynchronouslyBeforeTheNewLoad
{
  [self prefetch:@[ _a ]];
  [self.network.hang addObject:_b];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:@"1"];
  XCTAssertNotNil(h.imageLayer.contents);
  [h setSource:_b transition:0 recyclingKey:@"2"];
  [self spin:0.05];
  XCTAssertNil(h.imageLayer.contents, @"cleared before the new source arrives");
}

- (void)testLoadCancelledByANewerSourceEmitsNothing
{
  [self.network.hang addObject:_a];
  [self prefetch:@[ _b ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  [h setSource:_b transition:0 recyclingKey:nil];
  [h reset];
  [self.network fail:_a];
  [self.network release:_a];
  [self spin:0.1];
  XCTAssertEqual(h.events.count, 0u, @"neither onError nor onLoad for the superseded source");
}

- (void)testMissingCatalogImageEmitsErrorAndLeavesViewEmpty
{
  TrueImageHarness *h = [self harness];
  [h setSource:@"no_such_image" transition:0 recyclingKey:nil];
  XCTAssertEqualObjects(h.events, @[ @"error" ]);
  XCTAssertEqualObjects(h.payloads[0][@"source"], @"no_such_image");
  XCTAssertNil(h.imageLayer.contents);
}

- (void)testCatalogImageDrawsInTheSameFrameAndNeverFades
{
  TrueImageHarness *h = [self harness];
  [h setSource:@"TrueImageTestIcon" transition:300 recyclingKey:nil];
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
  XCTAssertFalse(h.isFading);
  XCTAssertNotNil(h.imageLayer.contents);
  XCTAssertEqualObjects(h.payloads[0][@"width"], @24, @"onLoad reports the catalog image's pixel size");
}

- (void)testCatalogImageRasterisesOnceItHasASize
{
  TrueImageHarness *h = [self harnessWithFrame:CGRectZero];
  [h setSource:@"TrueImageTestIcon" transition:0 recyclingKey:nil];
  XCTAssertEqual(h.events.count, 0u, @"nothing to draw at zero size");
  h.view.frame = CGRectMake(0, 0, 40, 40);
  [h.view layoutIfNeeded];
  XCTAssertEqualObjects(h.events, (@[ @"load", @"display", @"displayEnd" ]));
}

- (void)testTintAppliesToCatalogImagesOnly
{
  TrueImageHarness *icon = [self harness];
  icon.view.tint = UIColor.redColor;
  [icon setSource:@"TrueImageTestIcon" transition:0 recyclingKey:nil];
  UIColor *tinted = [TrueImageTestCase centerColorOf:(CGImageRef)icon.imageLayer.contents];
  CGFloat r, g, b, a;
  [tinted getRed:&r green:&g blue:&b alpha:&a];
  XCTAssertGreaterThan(r, 0.9);
  XCTAssertLessThan(g, 0.1);

  [self prefetch:@[ _a ]];
  TrueImageHarness *bitmap = [self harness];
  bitmap.view.tint = UIColor.blueColor;
  [bitmap setSource:_a transition:0 recyclingKey:nil];
  UIColor *untouched = [TrueImageTestCase centerColorOf:(CGImageRef)bitmap.imageLayer.contents];
  [untouched getRed:&r green:&g blue:&b alpha:&a];
  XCTAssertEqualWithAccuracy(r, 200 / 255.0, 0.02, @"remote bitmaps are never tinted");
  XCTAssertLessThan(b, 0.3);
}

- (void)testDynamicTintReRasterisesOnAppearanceChange
{
  UIColor *dynamic = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? UIColor.blueColor : UIColor.redColor;
  }];
  TrueImageHarness *h = [self harness];
  h.view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
  h.view.tint = dynamic;
  [h setSource:@"TrueImageTestIcon" transition:0 recyclingKey:nil];
  CGFloat r, g, b, a;
  [[TrueImageTestCase centerColorOf:(CGImageRef)h.imageLayer.contents] getRed:&r green:&g blue:&b alpha:&a];
  XCTAssertGreaterThan(r, 0.9);

  h.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
  // UIKit delivers trait changes on the next run loop turn.
  BOOL resolved = [self waitFor:^{
    CGFloat red, green, blue, alpha;
    [[TrueImageTestCase centerColorOf:(CGImageRef)h.imageLayer.contents] getRed:&red green:&green blue:&blue alpha:&alpha];
    return blue > 0.9;
  } timeout:1];
  XCTAssertTrue(resolved, @"the tint resolved against the new appearance");
  XCTAssertEqual(h.events.count, 3u, @"a re-rasterisation reports nothing new");
}

- (void)testResizeReRasterisesCatalogImageAtTheNewSize
{
  TrueImageHarness *h = [self harness];
  [h setSource:@"TrueImageTestIcon" transition:0 recyclingKey:nil];
  CGFloat scale = h.view.traitCollection.displayScale;
  XCTAssertEqual(CGImageGetWidth((CGImageRef)h.imageLayer.contents), (size_t)(40 * scale));
  h.view.frame = CGRectMake(0, 0, 80, 80);
  [h.view layoutIfNeeded];
  XCTAssertEqual(CGImageGetWidth((CGImageRef)h.imageLayer.contents), (size_t)(80 * scale));
}

- (void)testLargeImageIsRefinedToAThumbnailWithoutFade
{
  self.network.dataByURL[_a] = [TrueImageTestCase pngWithSize:CGSizeMake(400, 400) color:UIColor.greenColor];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:3]);
  size_t expected = (size_t)(40 * h.view.traitCollection.displayScale);
  XCTAssertTrue([self waitFor:^{
    return CGImageGetWidth((CGImageRef)h.imageLayer.contents) == expected;
  }], @"contents swapped for a thumbnail at the drawn pixel size");
  XCTAssertFalse(h.isFading);
  XCTAssertEqual(h.events.count, 3u, @"the swap reports nothing new");
}

- (void)testSmallImageIsNotRefined
{
  [self prefetch:@[ _a ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  [self spin:0.1];
  XCTAssertEqual(CGImageGetWidth((CGImageRef)h.imageLayer.contents), 8u);
}

- (void)testContentsNeverAnimateImplicitly
{
  [self prefetch:@[ _a, _b ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  [h setSource:_b transition:0 recyclingKey:nil];
  XCTAssertEqual(h.imageLayer.animationKeys.count, 0u);
}

- (void)testFailedRemoteLoadEmitsError
{
  [self.network.failAlways addObject:_a];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:nil];
  XCTAssertTrue([self waitForEvents:h count:1]);
  XCTAssertEqualObjects(h.events, @[ @"error" ]);
  XCTAssertEqualObjects(h.payloads[0][@"error"], @"HTTP 404");
}

- (void)testPrepareForRecycleClearsEverything
{
  [self prefetch:@[ _a ]];
  TrueImageHarness *h = [self harness];
  [h setSource:_a transition:0 recyclingKey:@"1"];
  [h.view prepareForRecycle];
  XCTAssertNil(h.imageLayer.contents);
  XCTAssertNil(h.view.source);
  XCTAssertNil(h.view.recyclingKey);
  XCTAssertNil(h.view.onLoad);
}

@end
