#import "TrueImageModule.h"

#import "TrueImageLoader.h"
#import "TrueImagePolicy.h"

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
    NSMutableDictionary<NSString *, NSString *> *headers = nil;
    if ([request[@"headers"] isKindOfClass:NSArray.class]) {
      headers = [NSMutableDictionary new];
      for (id header in request[@"headers"]) {
        if ([header isKindOfClass:NSDictionary.class] && [header[@"name"] isKindOfClass:NSString.class] &&
            [header[@"value"] isKindOfClass:NSString.class]) {
          headers[header[@"name"]] = header[@"value"];
        }
      }
    }
    [parsed addObject:[TrueImagePrefetchRequest requestWithURL:url headers:headers.count > 0 ? headers : nil]];
  }
  [TrueImageLoader prefetch:parsed
                 completion:^(BOOL ok) {
                   resolve(@(ok && allValid));
                 }];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTrueImageSpecJSI>(params);
}

@end
