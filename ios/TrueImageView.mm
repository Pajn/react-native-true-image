#import "TrueImageView.h"

#import <QuartzCore/QuartzCore.h>

#import "TrueImageLoader.h"
#import "TrueImageResources.h"
#import "TrueImageThumbnails.h"

static NSString *const kFadeKey = @"fade";

/// Identifies one load: the same source at a different blur, or blurred
/// from a differently shrunk copy, is a different image. Carries the
/// resolved shrink factor rather than the prop so a prop change that leaves
/// the factor alone (no blur, or a radius too small to shrink) is not a load.
struct TrueImageRequest {
  NSString *source;
  CGFloat blurRadius;
  CGFloat blurDownscale;

  bool operator==(const TrueImageRequest &other) const
  {
    return blurRadius == other.blurRadius && blurDownscale == other.blurDownscale &&
        [source isEqualToString:other.source];
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

  id _placeholderToken;
  /// The layer shows the placeholder; `_loadedKind` stays None.
  BOOL _placeholderShown;
  TrueImageRequest _placeholderRequest;
  UIImage *_placeholderImage;
  BOOL _placeholderIsResource;

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
  NSString *_appliedPlaceholder;
  /// Recycled while still on screen: clear once the view moves.
  BOOL _clearOnMove;
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
    _blurPixelsPerRadius = TrueImageDefaultBlurPixelsPerRadius;
    _loadedKind = TrueImageKind::None;
    [self applyGravity];
  }
  return self;
}

- (void)dealloc
{
  [TrueImageLoader cancel:_pendingToken];
  [TrueImageLoader cancel:_placeholderToken];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _imageLayer.frame = self.bounds;
  _imageLayer.contentsScale = [self displayScale];
  switch (_loadedKind) {
    case TrueImageKind::None:
      if (_placeholderShown && _placeholderIsResource) {
        [self showPlaceholder:_placeholderImage request:_placeholderRequest isResource:YES];
      }
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

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  if (_clearOnMove) {
    [self clear];
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
  // Reused before it moved: the old screen's pixels must not crossfade into
  // the new component's image.
  if (_clearOnMove) {
    [self clear];
  }
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
  BOOL placeholderChanged = _placeholder != _appliedPlaceholder && ![_placeholder isEqualToString:_appliedPlaceholder];
  _appliedPlaceholder = [_placeholder copy];

  if (_source.length == 0) {
    [self clear];
    return;
  }
  TrueImageRequest request{
      _source, _blurRadius, TrueImageBlurDownscaleFactor(_blurRadius, _blurPixelsPerRadius)};
  if (_loadedKind != TrueImageKind::None && _loadedRequest == request) {
    [self cancelPending];
    return;
  }
  if (_hasPending && _pendingRequest == request) {
    if (placeholderChanged) {
      [self loadPlaceholder];
    }
    return;
  }
  [self load:request];
}

/// A navigator can keep an unmounted screen on screen for its exit
/// animation, so a view recycled while still in a window keeps its pixels
/// and clears when it moves; off screen it clears at once.
- (void)prepareForRecycle
{
  if (self.window) {
    [self cancelPending];
    [self dropPlaceholder];
    _clearOnMove = YES;
  } else {
    [self clear];
  }
  _source = nil;
  _headers = nil;
  _recyclingKey = nil;
  _appliedRecyclingKey = nil;
  _transition = 0;
  _blurRadius = 0;
  _blurPixelsPerRadius = TrueImageDefaultBlurPixelsPerRadius;
  _tint = nil;
  _appliedTint = nil;
  _fitMode = TrueImageFitModeCover;
  _appliedFitMode = TrueImageFitModeCover;
  _placeholder = nil;
  _placeholderHeaders = nil;
  _appliedPlaceholder = nil;
  _placeholderTransition = 0;
  _placeholderFromNetwork = NO;
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
                        blurDownscale:request.blurDownscale
                              headers:_headers
                            cacheOnly:NO
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
    // Only an empty view gets a placeholder; a displayed image stays up
    // until its replacement arrives.
    if (_loadedKind == TrueImageKind::None) {
      [self loadPlaceholder];
    }
  }
}

/// Loads the placeholder for a pending source into an empty view. A
/// placeholder already showing is kept; a remote one is answered from the
/// cache unless it may hit the network. Silent on failure.
- (void)loadPlaceholder
{
  [TrueImageLoader cancel:_placeholderToken];
  _placeholderToken = nil;
  if (_placeholder.length == 0) {
    if (_placeholderShown) {
      [self dropPlaceholder];
      _imageLayer.contents = nil;
    }
    return;
  }
  TrueImageRequest request{
      _placeholder, _blurRadius, TrueImageBlurDownscaleFactor(_blurRadius, _blurPixelsPerRadius)};
  if (_placeholderShown && _placeholderRequest == request) {
    return;
  }
  NSURL *url = TrueImageURLFromSource(_placeholder);
  if (!url) {
    UIImage *image = [TrueImageResources imageNamed:_placeholder traits:self.traitCollection];
    if (image) {
      [self showPlaceholder:image request:request isResource:YES];
    }
    return;
  }
  [TrueImageLoader configureOnce];
  BOOL remote = [url.scheme hasPrefix:@"http"];
  NSUInteger gen = _generation;
  __weak __typeof(self) weakSelf = self;
  _placeholderToken = [TrueImageLoader loadURL:url
                                    blurRadius:request.blurRadius
                                 blurDownscale:request.blurDownscale
                                       headers:_placeholderHeaders
                                     cacheOnly:remote && !_placeholderFromNetwork
                                    completion:^(UIImage *image, BOOL fromMemory, NSString *error) {
                                      __typeof(self) self = weakSelf;
                                      // Stale once the image arrived or the source moved on.
                                      if (!self || self->_generation != gen || self->_loadedKind != TrueImageKind::None) {
                                        return;
                                      }
                                      self->_placeholderToken = nil;
                                      if (image) {
                                        [self showPlaceholder:image request:request isResource:NO];
                                      }
                                    }];
}

- (void)showPlaceholder:(UIImage *)image request:(TrueImageRequest)request isResource:(BOOL)isResource
{
  [self interruptFade];
  _placeholderShown = YES;
  _placeholderRequest = request;
  _placeholderImage = image;
  _placeholderIsResource = isResource;
  [self applyGravity];
  if (isResource) {
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
      return;
    }
    _imageLayer.contentsGravity = kCAGravityResize;
    _imageLayer.contents = (__bridge id)raster;
    CGImageRelease(raster);
  } else {
    _imageLayer.contents = (__bridge id)image.CGImage;
  }
  _imageLayer.opacity = 1;
}

/// Forgets the placeholder without touching the layer; the caller decides
/// what replaces its contents.
- (void)dropPlaceholder
{
  [TrueImageLoader cancel:_placeholderToken];
  _placeholderToken = nil;
  _placeholderShown = NO;
  _placeholderImage = nil;
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
  [self dropPlaceholder];
  _loadedKind = TrueImageKind::Resource;
  _loadedRequest = request;
  _loadedImage = image;
  _thumbnailKey = nil;
  _rasterSize = CGSizeZero;
  [self rasterize:image request:request];
}

- (void)cancelPending
{
  // Bump first: a cancel can run the completion synchronously with a
  // cancelled error, and it must already look stale when it does.
  _generation++;
  [TrueImageLoader cancel:_pendingToken];
  _pendingToken = nil;
  _hasPending = NO;
  [TrueImageLoader cancel:_placeholderToken];
  _placeholderToken = nil;
}

- (void)clear
{
  _clearOnMove = NO;
  [self cancelPending];
  [self dropPlaceholder];
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
  // Leaving a placeholder is its own transition; it is never a late arrival.
  NSInteger transitionMs = _placeholderShown ? _placeholderTransition : _transition;
  BOOL fade = TrueImageShouldFade(transitionMs, fromMemory, hasContents, NO);
  [self dropPlaceholder];
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
    [self runFadeTo:contents hasContents:hasContents durationMs:transitionMs];
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

- (void)runFadeTo:(id)contents hasContents:(BOOL)hasContents durationMs:(NSInteger)durationMs
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
  animation.duration = TrueImageFadeDuration(durationMs);

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
  NSString *key = TrueImageThumbnailKey(request.source, request.blurRadius, request.blurDownscale, size);
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
