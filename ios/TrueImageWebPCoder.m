#import "TrueImageWebPCoder.h"

#import <ImageIO/ImageIO.h>

@implementation TrueImageWebPCoder

+ (instancetype)sharedCoder
{
  static TrueImageWebPCoder *coder;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    coder = [TrueImageWebPCoder new];
  });
  return coder;
}

+ (SDImageFormat)imageFormat
{
  return SDImageFormatWebP;
}

+ (NSString *)imageUTType
{
  return @"org.webmproject.webp";
}

+ (NSString *)dictionaryProperty
{
  return @"{WebP}";
}

+ (NSString *)unclampedDelayTimeProperty
{
  return @"UnclampedDelayTime";
}

+ (NSString *)delayTimeProperty
{
  return @"DelayTime";
}

+ (NSString *)loopCountProperty
{
  return @"LoopCount";
}

+ (NSUInteger)defaultLoopCount
{
  return 0;
}

@end
