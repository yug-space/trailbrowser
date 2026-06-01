#import <Foundation/Foundation.h>

@class WKHTTPCookieStore;

NS_ASSUME_NONNULL_BEGIN

@interface ChromeProfile : NSObject
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *email;
@end

@interface ChromeCookieImportResult : NSObject
@property (nonatomic, assign) NSUInteger imported;
@property (nonatomic, assign) NSUInteger skipped;
@property (nonatomic, assign) NSUInteger decryptionFailures;
@property (nonatomic, assign) NSUInteger partitionedSkipped;
@end

@interface ChromeCookieImporter : NSObject

+ (BOOL)isChromeInstalled;

+ (NSArray<ChromeProfile *> *)availableProfiles;

+ (nullable NSArray<NSHTTPCookie *> *)cookiesForProfileDirectory:(NSString *)directory
                                                          error:(NSError **)error;

+ (void)importProfileDirectory:(NSString *)directory
                 intoCookieStore:(WKHTTPCookieStore *)store
                      completion:(void (^)(ChromeCookieImportResult *_Nullable result,
                                           NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
