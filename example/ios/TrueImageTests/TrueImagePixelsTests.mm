#import "TrueImageTestCase.h"

#import "TrueImageModule.h"
#import "TrueImagePixels.h"

/// The samples `getPixels` hands JS for colour extraction: row-major RGBA,
/// 8-bit and not premultiplied, loaded through the view's cache.
@interface TrueImagePixelsTests : TrueImageTestCase
@end

@implementation TrueImagePixelsTests {
  NSString *_url;
}

- (void)setUp
{
  [super setUp];
  _url = @"https://cdn.example.com/cover.jpg";
}

/// What the module resolves, decoded; nil when it resolved null.
- (NSData *)pixels:(NSString *)uri size:(double)size headers:(NSArray *)headers
{
  __block BOOL done = NO;
  __block id result;
  TrueImageModule *module = [TrueImageModule new];
  [module getPixels:uri
               size:size
            headers:headers
            resolve:^(id value) {
              result = value;
              done = YES;
            }
             reject:^(NSString *code, NSString *message, NSError *error) {
               XCTFail(@"getPixels rejected: %@", message);
             }];
  XCTAssertTrue([self waitFor:^{
    return done;
  }], @"getPixels did not complete");
  return [result isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:result options:0] : nil;
}

- (void)testResolvesTheImageAsRgbaAtTheRequestedSize
{
  NSData *data = [self pixels:_url size:16 headers:nil];
  XCTAssertEqual(data.length, 16u * 16u * 4u);
  // The fake network serves an opaque (200, 50, 50) square.
  const uint8_t *bytes = (const uint8_t *)data.bytes;
  for (NSUInteger i = 0; i < data.length; i += 4) {
    XCTAssertEqualWithAccuracy(bytes[i], 200, 1);
    XCTAssertEqualWithAccuracy(bytes[i + 1], 50, 1);
    XCTAssertEqualWithAccuracy(bytes[i + 2], 50, 1);
    XCTAssertEqual(bytes[i + 3], 255);
  }
}

- (void)testPassesHeadersThrough
{
  [self pixels:_url size:16 headers:@[ @{@"name" : @"Authorization", @"value" : @"Bearer t"} ]];
  XCTAssertEqualObjects(self.network.headersSeen[_url], (@{@"Authorization" : @"Bearer t"}));
}

- (void)testResolvesNullWhenTheLoadFails
{
  [self.network.failAlways addObject:_url];
  XCTAssertNil([self pixels:_url size:16 headers:nil]);
}

- (void)testResolvesNullForAnUnusableSize
{
  for (NSNumber *size in @[ @0, @-1, @(NAN), @257 ]) {
    XCTAssertNil([self pixels:_url size:size.doubleValue headers:nil]);
  }
  XCTAssertEqual([self.network fetchCount:_url], 0u);
}

- (void)testSamplingAPrefetchedURLSharesTheDownload
{
  XCTAssertTrue(([self prefetch:@[ _url ]]));
  XCTAssertNotNil([self pixels:_url size:16 headers:nil]);
  XCTAssertEqual([self.network fetchCount:_url], 1u);
}

- (void)testReportsTranslucentColoursUnpremultiplied
{
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
  format.scale = 1;
  UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4) format:format]
      imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithRed:200 / 255.0 green:100 / 255.0 blue:50 / 255.0 alpha:0.5] setFill];
        [context fillRect:CGRectMake(0, 0, 4, 4)];
      }];
  NSData *data = [TrueImagePixels rgbaFromImage:image size:2];
  XCTAssertEqual(data.length, 2u * 2u * 4u);
  const uint8_t *bytes = (const uint8_t *)data.bytes;
  XCTAssertEqualWithAccuracy(bytes[0], 200, 2);
  XCTAssertEqualWithAccuracy(bytes[1], 100, 2);
  XCTAssertEqualWithAccuracy(bytes[2], 50, 2);
  XCTAssertEqualWithAccuracy(bytes[3], 128, 1);
}

@end
