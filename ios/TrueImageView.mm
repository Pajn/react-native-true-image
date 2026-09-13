#import "TrueImageView.h"

#import <QuartzCore/QuartzCore.h>

#import "TrueImageLoader.h"
#import "TrueImageResources.h"
#import "TrueImageThumbnails.h"

static NSString *const kFadeKey = @"fade";

/// Identifies one load: the same source at a different blur is a different image.
struct TrueImageRequest {
  NSString *source;
  CGFloat blurRadius;

  bool operator==(const TrueImageRequest &other) const
  {
    return blurRadius == other.blurRadius && [source isEqualToString:other.source];
  }
};

enum class TrueImageKind { None, Bitmap, Resource };

/// Runs the fade's completion. Reports `finished == NO` when a newer fade
/// replaced this one so the interrupted image stays silent.
@interface TrueImageFadeDelegate : NSObject <CAAnimationDelegate>
@property (nonatomic, copy) void (^completion)(BOOL finished);
@end

@implementation TrueImageFadeDelegate
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
  if (_completion) {
    _completion(flag);
  }
}
@end

@implementation TrueImageView {
  CALayer *_imageLayer;

  TrueImageKind _loadedKind;
  TrueImageRequest _loadedRequest;
  UIImage *_loadedImage;

  BOOL _hasPending;
  TrueImageRequest _pendingRequest;
  id _pendingToken;

  /// Bumped whenever an in-flight load is abandoned; stale completions compare against it.
  NSUInteger _generation;
  /// Identifies the fade that is allowed to report onDisplayEnd.
  NSUInteger _fadeToken;

  BOOL _hasReported;
  TrueImageRequest _reportedRequest;
  NSString *_thumbnailKey;
  CGSize _rasterSize;

  NSString *_appliedRecyclingKey;
  TrueImageFitMode _appliedFitMode;
  UIColor *_appliedTint;
}

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    self.opaque = NO;
    _imageLayer = [CALayer layer];
    _imageLayer.masksToBounds = YES;
    _imageLayer.contentsScale = [self displayScale];
    // Setting contents, opacity or geometry must never install an implicit
    // animation under the fade; every fade is added explicitly.
    _imageLayer.actions = @{
      @"contents" : NSNull.null,
      @"opacity" : NSNull.null,
      @"bounds" : NSNull.null,
      @"position" : NSNull.null,
      @"contentsGravity" : NSNull.null,
    };
    [self.layer addSublayer:_imageLayer];
    _fitMode = TrueImageFitModeCover;
    _appliedFitMode = TrueImageFitModeCover;
    _loadedKind = TrueImageKind::None;
    [self applyGravity];
  }
  return self;
}

- (void)dealloc
{
  [TrueImageLoader cancel:_pendingToken];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _imageLayer.frame = self.bounds;
  _imageLayer.contentsScale = [self displayScale];
  switch (_loadedKind) {
    case TrueImageKind::None:
      break;
    case TrueImageKind::Resource:
      if (!CGSizeEqualToSize(self.bounds.size, _rasterSize)) {
        [self rasterize:_loadedImage request:_loadedRequest];
      }
      break;
    case TrueImageKind::Bitmap:
      [self refineContents:_loadedImage request:_loadedRequest];
      break;
  }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
  [super traitCollectionDidChange:previousTraitCollection];
  // Dynamic tints resolve differently per appearance; re-rasterise.
  if (_loadedKind == TrueImageKind::Resource) {
    [self rasterize:_loadedImage request:_loadedRequest];
  }
}

- (CGFloat)displayScale
{
  CGFloat scale = self.traitCollection.displayScale;
  return scale > 0 ? scale : UIScreen.mainScreen.scale;
}

#pragma mark - Fabric entry points

- (void)commit
{
  if (_recyclingKey != _appliedRecyclingKey && ![_recyclingKey isEqualToString:_appliedRecyclingKey]) {
    _appliedRecyclingKey = [_recyclingKey copy];
    [self clear];
  }
  if (_fitMode != _appliedFitMode) {
    _appliedFitMode = _fitMode;
    switch (_loadedKind) {
      case TrueImageKind::Resource:
        [self rasterize:_loadedImage request:_loadedRequest];
        break;
      case TrueImageKind::Bitmap:
        [self applyGravity];
        _thumbnailKey = nil;
        [self refineContents:_loadedImage request:_loadedRequest];
        break;
      case TrueImageKind::None:
        [self applyGravity];
        break;
    }
  }
  if (_tint != _appliedTint && ![_tint isEqual:_appliedTint]) {
    _appliedTint = _tint;
    if (_loadedKind == TrueImageKind::Resource) {
      [self rasterize:_loadedImage request:_loadedRequest];
    }
  }

  if (_source.length == 0) {
    [self clear];
    return;
  }
  TrueImageRequest request{_source, _blurRadius};
  if (_loadedKind != TrueImageKind::None && _loadedRequest == request) {
    [self cancelPending];
    return;
  }
  if (_hasPending && _pendingRequest == request) {
    return;
  }
  [self load:request];
}

- (void)prepareForRecycle
{
  [self clear];
  _source = nil;
  _headers = nil;
  _recyclingKey = nil;
  _appliedRecyclingKey = nil;
  _transition = 0;
  _blurRadius = 0;
  _tint = nil;
  _appliedTint = nil;
  _fitMode = TrueImageFitModeCover;
  _appliedFitMode = TrueImageFitModeCover;
  _onLoad = nil;
  _onError = nil;
  _onDisplay = nil;
  _onDisplayEnd = nil;
  [self applyGravity];
}

#pragma mark - Loading

- (void)load:(TrueImageRequest)request
{
  [self cancelPending];
  NSUInteger gen = _generation;

  NSURL *url = TrueImageURLFromSource(request.source);
  if (!url) {
    [self loadResource:request];
    return;
  }

  [TrueImageLoader configureOnce];
  __weak __typeof(self) weakSelf = self;
  id token = [TrueImageLoader loadURL:url
                           blurRadius:request.blurRadius
                              headers:_headers
                           completion:^(UIImage *image, BOOL fromMemory, NSString *error) {
                             __typeof(self) self = weakSelf;
                             // A load superseded by a newer source is silent: no onError, no image.
                             if (!self || self->_generation != gen) {
                               return;
                             }
                             self->_hasPending = NO;
                             self->_pendingToken = nil;
                             if (image) {
                               [self show:image request:request fromMemory:fromMemory];
                             } else if (self->_onError) {
                               self->_onError(error ?: @"Failed to load image", request.source);
                             }
                           }];
  // A memory hit completes synchronously inside loadURL; only track
  // operations that are still in flight.
  if (_generation == gen && !(_loadedKind != TrueImageKind::None && _loadedRequest == request)) {
    _hasPending = YES;
    _pendingRequest = request;
    _pendingToken = token;
  }
}

/// Scheme-less sources: inflated and drawn in the same frame, never faded.
- (void)loadResource:(TrueImageRequest)request
{
  UIImage *image = [TrueImageResources imageNamed:request.source traits:self.traitCollection];
  if (!image) {
    [self clear];
    if (_onError) {
      _onError([NSString stringWithFormat:@"No image named \"%@\" in the asset catalog", request.source],
               request.source);
    }
    return;
  }
  [self interruptFade];
  _loadedKind = TrueImageKind::Resource;
  _loadedRequest = request;
  _loadedImage = image;
  _thumbnailKey = nil;
  _rasterSize = CGSizeZero;
  [self rasterize:image request:request];
}

- (void)cancelPending
{
  [TrueImageLoader cancel:_pendingToken];
  _pendingToken = nil;
  _hasPending = NO;
  _generation++;
}

- (void)clear
{
  [self cancelPending];
  [self interruptFade];
  _imageLayer.contents = nil;
  _imageLayer.opacity = 1;
  _loadedKind = TrueImageKind::None;
  _loadedImage = nil;
  _hasReported = NO;
  _thumbnailKey = nil;
  _rasterSize = CGSizeZero;
}

#pragma mark - Display

- (void)show:(UIImage *)image request:(TrueImageRequest)request fromMemory:(BOOL)fromMemory
{
  // Read the model layer, not the presentation layer: a clear followed by a
  // new image inside one transaction must count as an empty layer.
  BOOL hasContents = _imageLayer.contents != nil;
  BOOL fade = TrueImageShouldFade(_transition, fromMemory, hasContents, NO);
  _loadedKind = TrueImageKind::Bitmap;
  _loadedRequest = request;
  _loadedImage = image;
  _hasReported = YES;
  _reportedRequest = request;
  _thumbnailKey = nil;
  id contents = (__bridge id)image.CGImage;
  [self applyGravity];

  if (_onLoad) {
    _onLoad(image.size.width * image.scale, image.size.height * image.scale, request.source);
  }

  if (fade) {
    [self runFadeTo:contents hasContents:hasContents];
    if (_onDisplay) {
      _onDisplay();
    }
  } else {
    [self interruptFade];
    _imageLayer.contents = contents;
    _imageLayer.opacity = 1;
    if (_onDisplay) {
      _onDisplay();
    }
    if (_onDisplayEnd) {
      _onDisplayEnd();
    }
  }
  [self refineContents:image request:request];
}

/// Removes a running fade. Its delegate sees `finished == NO` and stays
/// silent; the image that replaced it reports onDisplayEnd in its turn.
- (void)interruptFade
{
  _fadeToken++;
  [_imageLayer removeAnimationForKey:kFadeKey];
}

- (void)runFadeTo:(id)contents hasContents:(BOOL)hasContents
{
  CABasicAnimation *running = (CABasicAnimation *)[_imageLayer animationForKey:kFadeKey];
  BOOL resumingOpacity = [running isKindOfClass:CABasicAnimation.class] &&
      [running.keyPath isEqualToString:TrueImageFadeKeyPathName(TrueImageFadeKeyPathOpacity)];
  TrueImageFadeKeyPath keyPath = resumingOpacity ? TrueImageFadeKeyPathOpacity : TrueImageFadeKeyPathFor(hasContents);

  CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:TrueImageFadeKeyPathName(keyPath)];
  switch (keyPath) {
    case TrueImageFadeKeyPathOpacity: {
      // resumedFade: an image part-way in carries on from where it was.
      CGFloat from = resumingOpacity ? (_imageLayer.presentationLayer ?: _imageLayer).opacity : 0;
      animation.fromValue = @(from);
      animation.toValue = @1;
      _imageLayer.contents = contents;
      _imageLayer.opacity = 1;
      break;
    }
    case TrueImageFadeKeyPathContents:
      animation.fromValue = _imageLayer.contents;
      animation.toValue = contents;
      _imageLayer.contents = contents;
      break;
  }
  animation.duration = TrueImageFadeDuration(_transition);

  _fadeToken++;
  NSUInteger token = _fadeToken;
  __weak __typeof(self) weakSelf = self;
  TrueImageFadeDelegate *delegate = [TrueImageFadeDelegate new];
  delegate.completion = ^(BOOL finished) {
    __typeof(self) self = weakSelf;
    if (!self || !finished || self->_fadeToken != token) {
      return;
    }
    if (self->_onDisplayEnd) {
      self->_onDisplayEnd();
    }
  };
  animation.delegate = delegate;
  // Adding under the same key replaces any running fade.
  [_imageLayer addAnimation:animation forKey:kFadeKey];
}

- (void)applyGravity
{
  switch (_fitMode) {
    case TrueImageFitModeCover:
      _imageLayer.contentsGravity = kCAGravityResizeAspectFill;
      break;
    case TrueImageFitModeContain:
      _imageLayer.contentsGravity = kCAGravityResizeAspect;
      break;
    case TrueImageFitModeStretch:
      _imageLayer.contentsGravity = kCAGravityResize;
      break;
    case TrueImageFitModeCenter:
      _imageLayer.contentsGravity = kCAGravityCenter;
      break;
  }
}

/// Swaps in a thumbnail resampled to the drawn size when the image is far
/// larger than the view. Never fades; skips when the key is unchanged.
- (void)refineContents:(UIImage *)image request:(TrueImageRequest)request
{
  CGSize pixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
  CGSize size;
  if (!TrueImageThumbnailPixelSize(pixels, self.bounds.size, [self displayScale], _fitMode, &size)) {
    return;
  }
  NSString *key = TrueImageThumbnailKey(request.source, request.blurRadius, size);
  if ([key isEqualToString:_thumbnailKey]) {
    return;
  }
  _thumbnailKey = key;
  __weak __typeof(self) weakSelf = self;
  [TrueImageThumbnails.shared makeFromImage:image
                                  pixelSize:size
                                        key:key
                                 completion:^(CGImageRef thumb) {
                                   __typeof(self) self = weakSelf;
                                   if (!self || !thumb || ![self->_thumbnailKey isEqualToString:key] ||
                                       self->_loadedKind == TrueImageKind::None ||
                                       !(self->_loadedRequest == request)) {
                                     return;
                                   }
                                   self->_imageLayer.contents = (__bridge id)thumb;
                                 }];
}

/// Catalog images are rasterised at the view's size so vector assets stay
/// sharp on resize and tints resolve against the current traits.
- (void)rasterize:(UIImage *)image request:(TrueImageRequest)request
{
  CGSize pixelSize = CGSizeZero;
  CGImageRef raster = [TrueImageResources rasterize:image
                                               size:self.bounds.size
                                              scale:[self displayScale]
                                               tint:_tint
                                               mode:_fitMode
                                             traits:self.traitCollection
                                          pixelSize:&pixelSize];
  if (!raster) {
    // Zero bounds: layoutSubviews rasterises once there is a size.
    _rasterSize = CGSizeZero;
    return;
  }
  _rasterSize = self.bounds.size;
  [self interruptFade];
  _imageLayer.contentsGravity = kCAGravityResize;
  _imageLayer.contents = (__bridge id)raster;
  _imageLayer.opacity = 1;
  CGImageRelease(raster);
  if (!_hasReported || !(_reportedRequest == request)) {
    _hasReported = YES;
    _reportedRequest = request;
    if (_onLoad) {
      _onLoad(pixelSize.width, pixelSize.height, request.source);
    }
    if (_onDisplay) {
      _onDisplay();
    }
    if (_onDisplayEnd) {
      _onDisplayEnd();
    }
  }
}

@end
