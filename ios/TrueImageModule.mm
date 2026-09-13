#import "TrueImageModule.h"

#import "TrueImageLoader.h"
#import "TrueImagePolicy.h"

@implementation TrueImageModule

+ (NSString *)moduleName
{
  return @"TrueImage";
}

- (void)prefetch:(NSArray *)urls resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  [TrueImageLoader configureOnce];
  // Parse with the same rules the view uses; an unparseable source forces
  // a false result.
  NSMutableArray<NSURL *> *parsed = [NSMutableArray arrayWithCapacity:urls.count];
  BOOL allValid = YES;
  for (id url in urls) {
    NSURL *parsedURL = [url isKindOfClass:NSString.class] ? TrueImageURLFromSource(url) : nil;
    if (parsedURL) {
      [parsed addObject:parsedURL];
    } else {
      allValid = NO;
    }
  }
  [TrueImageLoader prefetchURLs:parsed
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
