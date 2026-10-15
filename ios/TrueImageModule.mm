#import "TrueImageModule.h"

#import "TrueImageLoader.h"
#import "TrueImagePixels.h"
#import "TrueImagePolicy.h"

/// Parses the `[{ name, value }]` list JS sends; nil when there is nothing to send.
static NSDictionary<NSString *, NSString *> *HeadersFromList(id list)
{
  if (![list isKindOfClass:NSArray.class]) return nil;
  NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary new];
  for (id header in list) {
    if ([header isKindOfClass:NSDictionary.class] && [header[@"name"] isKindOfClass:NSString.class] &&
        [header[@"value"] isKindOfClass:NSString.class]) {
      headers[header[@"name"]] = header[@"value"];
    }
  }
  return headers.count > 0 ? headers : nil;
}

@implementation TrueImageModule

+ (NSString *)moduleName
{
  return @"TrueImage";
}

- (void)prefetch:(NSArray *)requests resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  [TrueImageLoader configureOnce];
  // Parse with the same rules the view uses; an unparseable source forces
  // a false result.
  NSMutableArray<TrueImagePrefetchRequest *> *parsed = [NSMutableArray arrayWithCapacity:requests.count];
  BOOL allValid = YES;
  for (id entry in requests) {
    NSDictionary *request = [entry isKindOfClass:NSDictionary.class] ? entry : nil;
    NSString *uri = [request[@"uri"] isKindOfClass:NSString.class] ? request[@"uri"] : nil;
    NSURL *url = uri ? TrueImageURLFromSource(uri) : nil;
    if (!url) {
      allValid = NO;
      continue;
    }
    TrueImagePrefetchRequest *parsedRequest = [TrueImagePrefetchRequest requestWithURL:url
                                                                              headers:HeadersFromList(request[@"headers"])];
    CGFloat w = [request[@"displayWidth"] doubleValue];
    CGFloat h = [request[@"displayHeight"] doubleValue];
    CGFloat threshold = request[@"downsampleThreshold"] ? [request[@"downsampleThreshold"] doubleValue] : 2;
    if (!isfinite(w) || !isfinite(h) || w < 0 || h < 0 || (w > 0) != (h > 0) ||
        !isfinite(threshold) || (threshold != 0 && threshold < 1)) {
      allValid = NO;
      continue;
    }
    parsedRequest.pixelSize = CGSizeMake(round(w * UIScreen.mainScreen.scale), round(h * UIScreen.mainScreen.scale));
    parsedRequest.downsampleThreshold = threshold;
    NSString *mode = request[@"resizeMode"];
    parsedRequest.fitMode = [mode isEqualToString:@"contain"] ? TrueImageFitModeContain :
      [mode isEqualToString:@"stretch"] ? TrueImageFitModeStretch :
      [mode isEqualToString:@"center"] ? TrueImageFitModeCenter : TrueImageFitModeCover;
    [parsed addObject:parsedRequest];
  }
  [TrueImageLoader prefetch:parsed
                 completion:^(BOOL ok) {
                   resolve(@(ok && allValid));
                 }];
}

- (void)getPixels:(NSString *)uri
             size:(double)size
          headers:(NSArray *)headers
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject
{
  [TrueImageLoader configureOnce];
  NSUInteger side = isfinite(size) && size >= 1 && size <= TrueImagePixels.maxSize ? (NSUInteger)size : 0;
  [TrueImagePixels loadSource:uri
                      headers:HeadersFromList(headers)
                         size:side
                   completion:^(NSData *rgba) {
                     resolve([rgba base64EncodedStringWithOptions:0]);
                   }];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTrueImageSpecJSI>(params);
}

@end
