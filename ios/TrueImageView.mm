#import "TrueImageView.h"

#import <QuartzCore/QuartzCore.h>

#import <memory>
#import <vector>

#import "TrueImageLoader.h"
#import "TrueImageResources.h"
#import "TrueImageVariants.h"

static NSString *const kFadeKey = @"fade";

/// Identifies one load: the same source at a different blur, or blurred
/// from a differently shrunk copy, is a different image. Carries the
/// resolved shrink factor rather than the prop so a prop change that leaves
/// the factor alone (no blur, or a radius too small to shrink) is not a load.
struct TrueImageRequest {
  NSString *source;
  CGFloat blurRadius;
  CGFloat blurDownscale;
  CGSize pixelSize;
  TrueImageFitMode fitMode;
  CGFloat threshold;

  bool operator==(const TrueImageRequest &other) const
  {
    return CGSizeEqualToSize(pixelSize, other.pixelSize) && fitMode == other.fitMode && threshold == other.threshold &&
        blurRadius == other.blurRadius && blurDownscale == other.blurDownscale &&
        [source isEqualToString:other.source];
  }
};

enum class TrueImageKind { None, Bitmap, Resource };

/// Where an attempt may be answered from.
enum class TrueImageTier {
  /// The memory cache alone; checked synchronously and skipped on a miss.
  Memory,
  /// The memory and disk caches, never the network.
  Cache,
  /// Anywhere, the network included.
  Network,
};

/// One request that may answer a load. A load's attempts run in order
/// until one succeeds; for a source with a cacheKey they include other URLs
/// of the same picture.
struct TrueImageAttempt {
  TrueImageRequest request;
  TrueImageTier tier;
  NSDictionary<NSString *, NSString *> *headers;
  /// Recorded in TrueImageVariants when this attempt succeeds.
  NSString *cacheKey;
};

using TrueImageAttempts = std::shared_ptr<const std::vector<TrueImageAttempt>>;

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
  /// Bumped whenever a placeholder load is abandoned or replaced.
  NSUInteger _placeholderGeneration;
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
    _downsampleThreshold = 2;
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
  if (_source.length > 0 && !_clearOnMove) [self commit];
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
  if (_downsampleThreshold > 0 && _fitMode != TrueImageFitModeCenter && TrueImageURLFromSource(_source) &&
      (self.bounds.size.width <= 0 || self.bounds.size.height <= 0)) {
    [self cancelPending];
    return;
  }
  TrueImageRequest request = [self requestForSource:_source];
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
  _cacheKey = nil;
  _recyclingKey = nil;
  _appliedRecyclingKey = nil;
  _transition = 0;
  _downsampleThreshold = 2;
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

- (TrueImageRequest)requestForSource:(NSString *)source
{
  BOOL sized = _downsampleThreshold > 0 && _fitMode != TrueImageFitModeCenter && TrueImageURLFromSource(source);
  CGSize pixels = sized ? CGSizeMake(round(self.bounds.size.width * [self displayScale]),
                                     round(self.bounds.size.height * [self displayScale])) : CGSizeZero;
  CGFloat blurDownscale = TrueImageBlurDownscaleFactor(_blurRadius, _blurPixelsPerRadius);
  if (sized) pixels = [TrueImageLoader compatiblePixelSizeForURL:TrueImageURLFromSource(source) pixelSize:pixels
                                                     fitMode:_fitMode downsampleThreshold:_downsampleThreshold
                                                  blurRadius:_blurRadius blurDownscale:blurDownscale];
  return {source, _blurRadius, blurDownscale,
          pixels, sized ? _fitMode : TrueImageFitModeCover, sized ? _downsampleThreshold : 0};
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
  // Pending before the first attempt starts: a memory hit completes inside
  // it and clears this again.
  _hasPending = YES;
  _pendingRequest = request;
  [self run:[self attemptsFor:request] from:0 request:request generation:gen];
  // Only an empty view gets a placeholder; a displayed image stays up
  // until its replacement arrives.
  if (_generation == gen && _hasPending && _loadedKind == TrueImageKind::None) {
    [self loadPlaceholder];
  }
}

/// The requests that may answer `request`, in order. With a cacheKey and
/// variants big enough for this view, memory is checked for the URL and
/// then each variant before anything touches the disk, then the disk cache
/// likewise, and only then the network for the URL itself.
- (TrueImageAttempts)attemptsFor:(TrueImageRequest)request
{
  auto attempts = std::make_shared<std::vector<TrueImageAttempt>>();
  NSString *key = [self variantKeyFor:request.source];
  NSArray<TrueImageVariant *> *sufficient = key ? [self variantChoiceFor:key source:request.source].sufficient : @[];
  if (sufficient.count > 0) {
    attempts->push_back({request, TrueImageTier::Memory, _headers, key});
    for (TrueImageVariant *variant in sufficient) {
      attempts->push_back({[self requestForSource:variant.url], TrueImageTier::Memory, _headers, key});
    }
    attempts->push_back({request, TrueImageTier::Cache, _headers, key});
    for (TrueImageVariant *variant in sufficient) {
      attempts->push_back({[self requestForSource:variant.url], TrueImageTier::Cache, _headers, key});
    }
  }
  attempts->push_back({request, TrueImageTier::Network, _headers, key});
  return attempts;
}

/// The cacheKey to use for `source`, or nil when it takes no part in variant reuse.
- (NSString *)variantKeyFor:(NSString *)source
{
  if (_cacheKey.length == 0 || _fitMode == TrueImageFitModeCenter || !TrueImageURLFromSource(source)) {
    return nil;
  }
  return _cacheKey;
}

- (TrueImageVariantChoice *)variantChoiceFor:(NSString *)key source:(NSString *)source
{
  CGFloat scale = [self displayScale];
  CGSize pixels = CGSizeMake(round(self.bounds.size.width * scale), round(self.bounds.size.height * scale));
  return [TrueImageVariants choose:[TrueImageVariants variantsForKey:key]
                         excluding:source
                        viewPixels:pixels
                           fitMode:_fitMode];
}

/// Starts the first attempt from `index` that can run. A memory attempt
/// that is not in memory is skipped without a request, so a memory hit
/// anywhere in the list completes inside this call, just as an exact hit
/// does. Returns the operation, or nil when nothing was left to start.
- (id)start:(TrueImageAttempts)attempts
         from:(size_t)index
    completion:(void (^)(size_t attempt, UIImage *image, BOOL fromMemory, NSString *error))completion
{
  for (size_t i = index; i < attempts->size(); i++) {
    const TrueImageAttempt &attempt = (*attempts)[i];
    NSURL *url = TrueImageURLFromSource(attempt.request.source);
    if (!url) {
      continue;
    }
    if (attempt.tier == TrueImageTier::Memory &&
        ![TrueImageLoader isInMemoryURL:url
                             blurRadius:attempt.request.blurRadius
                          blurDownscale:attempt.request.blurDownscale
                              pixelSize:attempt.request.pixelSize
                                fitMode:attempt.request.fitMode
                    downsampleThreshold:attempt.request.threshold]) {
      continue;
    }
    return [TrueImageLoader loadURL:url
                         blurRadius:attempt.request.blurRadius
                      blurDownscale:attempt.request.blurDownscale
                            headers:attempt.headers
                          cacheOnly:attempt.tier != TrueImageTier::Network
                          pixelSize:attempt.request.pixelSize
                            fitMode:attempt.request.fitMode
                downsampleThreshold:attempt.request.threshold
                           cacheKey:attempt.cacheKey
                         completion:^(UIImage *image, BOOL fromMemory, NSString *error) {
                           completion(i, image, fromMemory, error);
                         }];
  }
  completion(attempts->size(), nil, NO, nil);
  return nil;
}

/// Forgets a variant the index promised but a cache-only lookup could not find.
static void ForgetIfEvicted(const TrueImageAttempt &attempt, NSString *requested)
{
  if (attempt.tier == TrueImageTier::Cache && attempt.cacheKey &&
      ![attempt.request.source isEqualToString:requested]) {
    [TrueImageVariants forgetURL:attempt.request.source forKey:attempt.cacheKey];
  }
}

/// Answers the pending load from the first of `attempts` that succeeds.
/// The next attempt starts as each fails; the last failure is the load's.
- (void)run:(TrueImageAttempts)attempts
          from:(size_t)index
       request:(TrueImageRequest)request
    generation:(NSUInteger)gen
{
  __weak __typeof(self) weakSelf = self;
  id token = [self start:attempts
                    from:index
              completion:^(size_t i, UIImage *image, BOOL fromMemory, NSString *error) {
                __typeof(self) self = weakSelf;
                // A load superseded by a newer source is silent: no onError, no image.
                if (!self || self->_generation != gen) {
                  return;
                }
                if (image) {
                  self->_hasPending = NO;
                  self->_pendingToken = nil;
                  [self show:image request:request fromMemory:fromMemory];
                  return;
                }
                if (i + 1 < attempts->size()) {
                  ForgetIfEvicted((*attempts)[i], request.source);
                  // Started outside SDWebImage's completion, which may still
                  // be unwinding the failed operation.
                  dispatch_async(dispatch_get_main_queue(), ^{
                    __typeof(self) self = weakSelf;
                    if (self && self->_generation == gen) {
                      [self run:attempts from:i + 1 request:request generation:gen];
                    }
                  });
                  return;
                }
                self->_hasPending = NO;
                self->_pendingToken = nil;
                if (self->_onError) {
                  self->_onError(error ?: @"Failed to load image", request.source);
                }
              }];
  // A memory hit completes synchronously inside the start; only track
  // operations that are still in flight.
  if (_generation == gen && _hasPending) {
    _pendingToken = token;
  }
}

/// Loads the placeholder for a pending source into an empty view. A
/// placeholder already showing is kept while it is still wanted; a remote
/// one is answered from the cache unless it may hit the network. Silent on
/// failure.
///
/// With a cacheKey, the largest cached variant of the source that is too
/// small to stand in for it is the placeholder: it is the same picture. It
/// wins over a remote cache-only placeholder, which is tried after it; a
/// local or network placeholder is the app's explicit choice and is used
/// alone.
- (void)loadPlaceholder
{
  // Bump first, as in cancelPending.
  _placeholderGeneration++;
  [TrueImageLoader cancel:_placeholderToken];
  _placeholderToken = nil;
  NSString *explicitSource = _placeholder.length > 0 ? _placeholder : nil;
  NSURL *explicitURL = explicitSource ? TrueImageURLFromSource(explicitSource) : nil;
  BOOL explicitRemote = [explicitURL.scheme hasPrefix:@"http"];
  BOOL explicitOnly = explicitSource && (!explicitRemote || _placeholderFromNetwork);
  NSString *key = _source.length > 0 && !explicitOnly ? [self variantKeyFor:_source] : nil;
  NSArray<TrueImageVariant *> *smaller = key ? [self variantChoiceFor:key source:_source].smaller : @[];
  auto attempts = std::make_shared<std::vector<TrueImageAttempt>>();

  if (smaller.count == 0) {
    if (!explicitSource) {
      if (_placeholderShown) {
        [self dropPlaceholder];
        _imageLayer.contents = nil;
      }
      return;
    }
    TrueImageRequest request = [self requestForSource:explicitSource];
    if (_placeholderShown && _placeholderRequest == request) {
      return;
    }
    if (!explicitURL) {
      UIImage *image = [TrueImageResources imageNamed:explicitSource traits:self.traitCollection];
      if (image) {
        [self showPlaceholder:image request:request isResource:YES];
      }
      return;
    }
    TrueImageTier tier = explicitRemote && !_placeholderFromNetwork ? TrueImageTier::Cache : TrueImageTier::Network;
    attempts->push_back({request, tier, _placeholderHeaders, nil});
  } else {
    if (_placeholderShown) {
      for (TrueImageVariant *variant in smaller) {
        if ([variant.url isEqualToString:_placeholderRequest.source]) {
          return;
        }
      }
      if ([explicitSource isEqualToString:_placeholderRequest.source]) {
        return;
      }
    }
    for (TrueImageVariant *variant in smaller) {
      attempts->push_back({[self requestForSource:variant.url], TrueImageTier::Memory, _headers, key});
    }
    if (explicitSource) {
      attempts->push_back({[self requestForSource:explicitSource], TrueImageTier::Memory, _placeholderHeaders, nil});
    }
    for (TrueImageVariant *variant in smaller) {
      attempts->push_back({[self requestForSource:variant.url], TrueImageTier::Cache, _headers, key});
    }
    if (explicitSource) {
      attempts->push_back({[self requestForSource:explicitSource], TrueImageTier::Cache, _placeholderHeaders, nil});
    }
  }
  [TrueImageLoader configureOnce];
  [self runPlaceholder:attempts from:0];
}

- (void)runPlaceholder:(TrueImageAttempts)attempts from:(size_t)index
{
  NSUInteger gen = _generation;
  NSUInteger placeholderGen = _placeholderGeneration;
  NSString *requested = _source;
  __weak __typeof(self) weakSelf = self;
  BOOL (^stale)(__typeof(self)) = ^BOOL(__typeof(self) self) {
    // Stale once the image arrived, the source moved on or another placeholder was asked for.
    return !self || self->_generation != gen || self->_placeholderGeneration != placeholderGen ||
        self->_loadedKind != TrueImageKind::None;
  };
  id token = [self start:attempts
                    from:index
              completion:^(size_t i, UIImage *image, BOOL fromMemory, NSString *error) {
                __typeof(self) self = weakSelf;
                if (stale(self)) {
                  return;
                }
                self->_placeholderToken = nil;
                if (image) {
                  [self showPlaceholder:image request:(*attempts)[i].request isResource:NO];
                  return;
                }
                if (i + 1 < attempts->size()) {
                  ForgetIfEvicted((*attempts)[i], requested);
                  dispatch_async(dispatch_get_main_queue(), ^{
                    __typeof(self) self = weakSelf;
                    if (!stale(self)) {
                      [self runPlaceholder:attempts from:i + 1];
                    }
                  });
                }
              }];
  if (!stale(self)) {
    _placeholderToken = token;
  }
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
  _placeholderGeneration++;
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

/// Catalog images rasterise at the view size so vectors remain sharp on resize.
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
