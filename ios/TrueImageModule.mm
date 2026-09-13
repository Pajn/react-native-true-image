#import "TrueImageModule.h"

#if __has_include(<TrueImage/TrueImage-Swift.h>)
#import <TrueImage/TrueImage-Swift.h>
#else
#import "TrueImage-Swift.h"
#endif

@implementation TrueImageModule

+ (NSString *)moduleName
{
  return @"TrueImage";
}

- (void)prefetch:(NSArray *)urls resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  NSMutableArray<NSString *> *sources = [NSMutableArray arrayWithCapacity:urls.count];
  for (id url in urls) {
    if ([url isKindOfClass:NSString.class]) {
      [sources addObject:url];
    }
  }
  [TrueImagePrefetch prefetch:sources
                 completion:^(BOOL ok) {
                   resolve(@(ok));
                 }];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTrueImageSpecJSI>(params);
}

@end
