#import "TrueImageComponentView.h"

#import <React/RCTConversions.h>

#import <react/renderer/components/TrueImageSpec/ComponentDescriptors.h>
#import <react/renderer/components/TrueImageSpec/EventEmitters.h>
#import <react/renderer/components/TrueImageSpec/Props.h>
#import <react/renderer/components/TrueImageSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

#if __has_include(<TrueImage/TrueImage-Swift.h>)
#import <TrueImage/TrueImage-Swift.h>
#else
#import "TrueImage-Swift.h"
#endif

using namespace facebook::react;

static TrueImageFitMode TrueImageFitModeFromProp(TrueImageViewResizeMode mode)
{
  switch (mode) {
    case TrueImageViewResizeMode::Contain:
      return TrueImageFitModeContain;
    case TrueImageViewResizeMode::Stretch:
      return TrueImageFitModeStretch;
    case TrueImageViewResizeMode::Center:
      return TrueImageFitModeCenter;
    case TrueImageViewResizeMode::Cover:
    default:
      return TrueImageFitModeCover;
  }
}

@implementation TrueImageComponentView {
  TrueImageView *_view;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<TrueImageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const TrueImageViewProps>();
    _props = defaultProps;

    _view = [[TrueImageView alloc] initWithFrame:frame];
    [self attachEventHandlers];
    self.contentView = _view;
  }
  return self;
}

- (void)attachEventHandlers
{
  __weak __typeof(self) weakSelf = self;
  _view.onLoad = ^(CGFloat width, CGFloat height, NSString *source) {
    __typeof(self) self = weakSelf;
    if (auto emitter = [self emitter]) {
      emitter->onLoad({.width = (Float)width, .height = (Float)height, .source = RCTStringFromNSString(source)});
    }
  };
  _view.onError = ^(NSString *message, NSString *source) {
    __typeof(self) self = weakSelf;
    if (auto emitter = [self emitter]) {
      emitter->onError({.error = RCTStringFromNSString(message), .source = RCTStringFromNSString(source)});
    }
  };
  _view.onDisplay = ^{
    __typeof(self) self = weakSelf;
    if (auto emitter = [self emitter]) {
      emitter->onDisplay({});
    }
  };
  _view.onDisplayEnd = ^{
    __typeof(self) self = weakSelf;
    if (auto emitter = [self emitter]) {
      emitter->onDisplayEnd({});
    }
  };
}

- (const TrueImageViewEventEmitter *)emitter
{
  if (!_eventEmitter) {
    return nullptr;
  }
  return static_cast<const TrueImageViewEventEmitter *>(_eventEmitter.get());
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &newProps = *std::static_pointer_cast<TrueImageViewProps const>(props);

  _view.source = newProps.source.empty() ? nil : RCTNSStringFromString(newProps.source);
  _view.fitMode = TrueImageFitModeFromProp(newProps.resizeMode);
  _view.transition = newProps.transition;
  _view.blurRadius = newProps.blurRadius;
  _view.tint = RCTUIColorFromSharedColor(newProps.tintColor);
  _view.recyclingKey = newProps.recyclingKey.empty() ? nil : RCTNSStringFromString(newProps.recyclingKey);

  [super updateProps:props oldProps:oldProps];
}

- (void)finalizeUpdates:(RNComponentViewUpdateMask)updateMask
{
  [super finalizeUpdates:updateMask];
  // Props and layout for one mount land in the same transaction; commit
  // once both are in place so resources rasterise at their real size.
  if (updateMask & RNComponentViewUpdateMaskProps) {
    [_view commit];
  }
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  [_view prepareForRecycle];
  [self attachEventHandlers];
}

@end
