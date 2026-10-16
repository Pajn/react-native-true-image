#import "TrueImageVariants.h"

static NSUInteger const kMaxKeys = 2000;
static NSUInteger const kMaxVariants = 8;
static NSInteger const kVersion = 1;
static NSTimeInterval const kWriteDelay = 1;

@implementation TrueImageVariant

+ (instancetype)variantWithURL:(NSString *)url pixelSize:(CGSize)pixelSize
{
  TrueImageVariant *variant = [TrueImageVariant new];
  variant->_url = [url copy];
  variant->_pixelSize = pixelSize;
  return variant;
}

- (CGFloat)area
{
  return _pixelSize.width * _pixelSize.height;
}

- (BOOL)isEqual:(id)object
{
  if (![object isKindOfClass:TrueImageVariant.class]) return NO;
  TrueImageVariant *other = object;
  return [_url isEqualToString:other.url] && CGSizeEqualToSize(_pixelSize, other.pixelSize);
}

- (NSUInteger)hash
{
  return _url.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@ %gx%g", _url, (double)_pixelSize.width, (double)_pixelSize.height];
}

@end

@implementation TrueImageVariantChoice

+ (instancetype)choiceWithSufficient:(NSArray *)sufficient smaller:(NSArray *)smaller
{
  TrueImageVariantChoice *choice = [TrueImageVariantChoice new];
  choice->_sufficient = [sufficient copy];
  choice->_smaller = [smaller copy];
  return choice;
}

@end

/// Keys and their variants, guarded by `Lock()`. `Order` lists keys least
/// recently used first.
static NSMutableDictionary<NSString *, NSMutableArray<TrueImageVariant *> *> *Keys(void)
{
  static NSMutableDictionary *keys;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ keys = [NSMutableDictionary new]; });
  return keys;
}

static NSMutableOrderedSet<NSString *> *Order(void)
{
  static NSMutableOrderedSet *order;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ order = [NSMutableOrderedSet new]; });
  return order;
}

static id Lock(void)
{
  static id lock;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ lock = [NSObject new]; });
  return lock;
}

/// File reads and writes, in order: the first read is queued before any write.
static dispatch_queue_t Queue(void)
{
  static dispatch_queue_t queue;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    queue = dispatch_queue_create("true-image-variants", dispatch_queue_attr_make_with_qos_class(
                                                             DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
  });
  return queue;
}

static BOOL gAttached;
static BOOL gWriteScheduled;
/// Bumped by reload and reset so a read queued before them is dropped.
static NSUInteger gEpoch;

/// Marks `key` most recently used and evicts the least recently used past the bound. Call under the lock.
static void Touch(NSString *key)
{
  NSMutableOrderedSet *order = Order();
  [order removeObject:key];
  [order addObject:key];
  while (order.count > kMaxKeys) {
    NSString *eldest = order.firstObject;
    [order removeObjectAtIndex:0];
    [Keys() removeObjectForKey:eldest];
  }
}

/// Keys in least-recently-used order. Malformed entries are skipped.
static NSArray<NSArray *> *Parse(NSData *data)
{
  id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![root isKindOfClass:NSDictionary.class] || ![root[@"version"] isEqual:@(kVersion)] ||
      ![root[@"keys"] isKindOfClass:NSArray.class]) {
    return nil;
  }
  NSMutableArray *result = [NSMutableArray new];
  for (id entry in root[@"keys"]) {
    if (![entry isKindOfClass:NSDictionary.class]) continue;
    NSString *key = entry[@"key"];
    NSArray *list = entry[@"variants"];
    if (![key isKindOfClass:NSString.class] || key.length == 0 || ![list isKindOfClass:NSArray.class]) continue;
    NSMutableArray *variants = [NSMutableArray new];
    for (id item in list) {
      if (![item isKindOfClass:NSDictionary.class]) continue;
      NSString *url = item[@"url"];
      id width = item[@"width"];
      id height = item[@"height"];
      if (![url isKindOfClass:NSString.class] || url.length == 0 || ![width isKindOfClass:NSNumber.class] ||
          ![height isKindOfClass:NSNumber.class] || [width doubleValue] <= 0 || [height doubleValue] <= 0) {
        continue;
      }
      [variants addObject:[TrueImageVariant variantWithURL:url
                                                 pixelSize:CGSizeMake([width doubleValue], [height doubleValue])]];
    }
    while (variants.count > kMaxVariants) [variants removeObjectAtIndex:0];
    if (variants.count > 0) [result addObject:@[ key, variants ]];
  }
  return result;
}

static NSData *Serialize(void)
{
  NSMutableArray *entries = [NSMutableArray arrayWithCapacity:Order().count];
  for (NSString *key in Order()) {
    NSMutableArray *variants = [NSMutableArray new];
    for (TrueImageVariant *variant in Keys()[key]) {
      [variants addObject:@{
        @"url" : variant.url,
        @"width" : @(variant.pixelSize.width),
        @"height" : @(variant.pixelSize.height),
      }];
    }
    [entries addObject:@{@"key" : key, @"variants" : variants}];
  }
  return [NSJSONSerialization dataWithJSONObject:@{@"version" : @(kVersion), @"keys" : entries} options:0 error:nil];
}

/// Writes a temporary file and renames it over the index, so a crash leaves the old one whole.
static void Write(void)
{
  NSData *data;
  @synchronized (Lock()) {
    gWriteScheduled = NO;
    data = Serialize();
  }
  [data writeToURL:TrueImageVariants.fileURL options:NSDataWritingAtomic error:nil];
}

/// Coalesces the records of a burst, such as a prefetch batch, into one write. Call under the lock.
static void ScheduleWrite(void)
{
  if (gWriteScheduled) return;
  gWriteScheduled = YES;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWriteDelay * NSEC_PER_SEC)), Queue(), ^{
    Write();
  });
}

/// Merges the file under what this process recorded before it landed;
/// those records are newer and win.
static void Read(NSUInteger epoch)
{
  NSURL *file = TrueImageVariants.fileURL;
  NSData *data = [NSData dataWithContentsOfURL:file];
  NSArray<NSArray *> *loaded = Parse(data);
  if (data && !loaded) {
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
  }
  @synchronized (Lock()) {
    if (epoch != gEpoch) return;
    // A copy: an ordered set's array follows the set, which is about to be refilled.
    NSArray<NSString *> *recentOrder = [Order().array copy];
    NSDictionary *recent = [Keys() copy];
    [Keys() removeAllObjects];
    [Order() removeAllObjects];
    for (NSArray *entry in loaded) {
      Keys()[entry[0]] = [entry[1] mutableCopy];
      Touch(entry[0]);
    }
    for (NSString *key in recentOrder) {
      NSArray<TrueImageVariant *> *mine = recent[key];
      if (mine.count == 0) continue;
      NSMutableArray *merged = [NSMutableArray new];
      for (TrueImageVariant *old in Keys()[key]) {
        if ([mine indexOfObjectPassingTest:^BOOL(TrueImageVariant *v, NSUInteger i, BOOL *stop) {
              return [v.url isEqualToString:old.url];
            }] == NSNotFound) {
          [merged addObject:old];
        }
      }
      [merged addObjectsFromArray:mine];
      while (merged.count > kMaxVariants) [merged removeObjectAtIndex:0];
      Keys()[key] = merged;
      Touch(key);
    }
  }
}

/// Starts reading the persisted index, once per process. Call under the lock.
static void Attach(void)
{
  if (gAttached) return;
  gAttached = YES;
  NSUInteger epoch = gEpoch;
  dispatch_async(Queue(), ^{ Read(epoch); });
}

@implementation TrueImageVariants

+ (NSUInteger)maxKeys
{
  return kMaxKeys;
}

+ (NSUInteger)maxVariants
{
  return kMaxVariants;
}

+ (NSURL *)fileURL
{
  NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
  return [caches URLByAppendingPathComponent:@"true-image-variants.json"];
}

+ (TrueImageVariantChoice *)choose:(NSArray<TrueImageVariant *> *)variants
                         excluding:(NSString *)excluded
                        viewPixels:(CGSize)viewPixels
                           fitMode:(TrueImageFitMode)mode
{
  NSMutableArray<TrueImageVariant *> *sufficient = [NSMutableArray new];
  NSMutableArray<TrueImageVariant *> *smaller = [NSMutableArray new];
  for (TrueImageVariant *variant in variants) {
    if (excluded && [variant.url isEqualToString:excluded]) continue;
    [(TrueImageVariantSuffices(variant.pixelSize, viewPixels, mode) ? sufficient : smaller) addObject:variant];
  }
  NSSortDescriptor *byArea = [NSSortDescriptor sortDescriptorWithKey:@"area" ascending:YES];
  [sufficient sortUsingDescriptors:@[ byArea ]];
  [smaller sortUsingDescriptors:@[ [byArea reversedSortDescriptor] ]];
  return [TrueImageVariantChoice choiceWithSufficient:sufficient smaller:smaller];
}

+ (NSArray<TrueImageVariant *> *)variantsForKey:(NSString *)key
{
  @synchronized (Lock()) {
    Attach();
    NSArray *variants = Keys()[key];
    if (!variants) return @[];
    Touch(key);
    return [variants copy];
  }
}

+ (void)recordURL:(NSString *)url pixelSize:(CGSize)pixelSize forKey:(NSString *)key
{
  if (url.length == 0 || key.length == 0 || pixelSize.width <= 0 || pixelSize.height <= 0) return;
  @synchronized (Lock()) {
    Attach();
    NSMutableArray<TrueImageVariant *> *list = Keys()[key];
    if (!list) {
      list = [NSMutableArray new];
      Keys()[key] = list;
    }
    for (TrueImageVariant *known in list) {
      // A reduced decode that SDWebImage stored and read back reports its
      // own size, not the URL's; never let it shrink what is known.
      if ([known.url isEqualToString:url]) {
        pixelSize = CGSizeMake(MAX(pixelSize.width, known.pixelSize.width), MAX(pixelSize.height, known.pixelSize.height));
      }
    }
    [list filterUsingPredicate:[NSPredicate predicateWithFormat:@"url != %@", url]];
    [list addObject:[TrueImageVariant variantWithURL:url pixelSize:pixelSize]];
    while (list.count > kMaxVariants) [list removeObjectAtIndex:0];
    Touch(key);
    ScheduleWrite();
  }
}

+ (void)forgetURL:(NSString *)url forKey:(NSString *)key
{
  @synchronized (Lock()) {
    Attach();
    NSMutableArray<TrueImageVariant *> *list = Keys()[key];
    NSUInteger before = list.count;
    [list filterUsingPredicate:[NSPredicate predicateWithFormat:@"url != %@", url]];
    if (list.count == before) return;
    if (list.count == 0) {
      [Keys() removeObjectForKey:key];
      [Order() removeObject:key];
    }
    ScheduleWrite();
  }
}

+ (void)flush
{
  dispatch_sync(Queue(), ^{
    BOOL pending;
    @synchronized (Lock()) {
      pending = gWriteScheduled;
    }
    if (pending) Write();
  });
}

+ (void)reload
{
  @synchronized (Lock()) {
    gEpoch++;
    gAttached = NO;
    gWriteScheduled = NO;
    [Keys() removeAllObjects];
    [Order() removeAllObjects];
    Attach();
  }
  dispatch_sync(Queue(), ^{});
}

+ (void)reset
{
  dispatch_sync(Queue(), ^{});
  @synchronized (Lock()) {
    gEpoch++;
    gAttached = YES;
    gWriteScheduled = NO;
    [Keys() removeAllObjects];
    [Order() removeAllObjects];
  }
  [NSFileManager.defaultManager removeItemAtURL:self.fileURL error:nil];
}

@end
