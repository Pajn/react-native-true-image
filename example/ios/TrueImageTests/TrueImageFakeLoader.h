#import <Foundation/Foundation.h>
#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

/// Serves images from memory so every fetch can be counted, failed or held.
@interface TrueImageFakeLoader : NSObject <SDImageLoader>

/// Bytes served for every URL unless overridden per URL.
@property (nonatomic, strong) NSData *defaultData;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSData *> *dataByURL;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSNumber *> *fetches;
/// Headers the last request for each URL carried, as applied by the request modifier.
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *headersSeen;
@property (nonatomic, strong, readonly) NSMutableSet<NSString *> *failOnce;
@property (nonatomic, strong, readonly) NSMutableSet<NSString *> *failAlways;
/// URLs whose fetch is held until `release:` or `fail:`.
@property (nonatomic, strong, readonly) NSMutableSet<NSString *> *hang;

- (NSUInteger)fetchCount:(NSString *)url;
- (void)release:(NSString *)url;
- (void)fail:(NSString *)url;

@end

NS_ASSUME_NONNULL_END
