#import "TrueImageFakeLoader.h"

@interface TrueImageFakeOperation : NSObject <SDWebImageOperation>
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation TrueImageFakeOperation
- (void)cancel
{
  self.cancelled = YES;
}
@end

@implementation TrueImageFakeLoader {
  NSMutableDictionary<NSString *, void (^)(void)> *_held;
}

- (instancetype)init
{
  if (self = [super init]) {
    _dataByURL = [NSMutableDictionary new];
    _fetches = [NSMutableDictionary new];
    _headersSeen = [NSMutableDictionary new];
    _failOnce = [NSMutableSet new];
    _failAlways = [NSMutableSet new];
    _hang = [NSMutableSet new];
    _held = [NSMutableDictionary new];
  }
  return self;
}

- (NSUInteger)fetchCount:(NSString *)url
{
  return _fetches[url].unsignedIntegerValue;
}

- (void)release:(NSString *)url
{
  void (^deliver)(void) = _held[url];
  [_held removeObjectForKey:url];
  if (deliver) {
    deliver();
  }
}

- (void)fail:(NSString *)url
{
  [_held removeObjectForKey:url];
  [_failAlways addObject:url];
}

- (BOOL)canRequestImageForURL:(NSURL *)url
{
  return YES;
}

- (BOOL)canRequestImageForURL:(NSURL *)url options:(SDWebImageOptions)options context:(SDWebImageContext *)context
{
  return YES;
}

/// Mirrors the real downloader: a failed URL is blacklisted unless the
/// caller passed `.retryFailed`.
- (BOOL)shouldBlockFailedURLWithURL:(NSURL *)url error:(NSError *)error
{
  return YES;
}

- (BOOL)shouldBlockFailedURLWithURL:(NSURL *)url
                              error:(NSError *)error
                            options:(SDWebImageOptions)options
                            context:(SDWebImageContext *)context
{
  return YES;
}

- (id<SDWebImageOperation>)requestImageWithURL:(NSURL *)url
                                       options:(SDWebImageOptions)options
                                       context:(SDWebImageContext *)context
                                      progress:(SDImageLoaderProgressBlock)progressBlock
                                     completed:(SDImageLoaderCompletedBlock)completedBlock
{
  NSString *key = url.absoluteString;
  _fetches[key] = @([self fetchCount:key] + 1);
  id<SDWebImageDownloaderRequestModifier> modifier = context[SDWebImageContextDownloadRequestModifier];
  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  if (modifier) {
    request = [modifier modifiedRequestWithRequest:request] ?: request;
  }
  _headersSeen[key] = request.allHTTPHeaderFields ?: @{};
  TrueImageFakeOperation *operation = [TrueImageFakeOperation new];

  BOOL fails = [_failAlways containsObject:key] || [_failOnce containsObject:key];
  [_failOnce removeObject:key];
  NSData *data = _dataByURL[key] ?: _defaultData;

  void (^deliver)(void) = ^{
    if (operation.cancelled) {
      return;
    }
    if (fails || [self->_failAlways containsObject:key]) {
      NSError *error = [NSError errorWithDomain:SDWebImageErrorDomain
                                           code:SDWebImageErrorInvalidDownloadStatusCode
                                       userInfo:@{NSLocalizedDescriptionKey : @"HTTP 404"}];
      completedBlock(nil, nil, error, YES);
      return;
    }
    UIImage *image = SDImageLoaderDecodeImageData(data, url, options, context);
    completedBlock(image, data, nil, YES);
  };

  if ([_hang containsObject:key]) {
    _held[key] = deliver;
  } else {
    dispatch_async(dispatch_get_main_queue(), deliver);
  }
  return operation;
}

@end
