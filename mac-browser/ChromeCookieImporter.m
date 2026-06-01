#import "ChromeCookieImporter.h"

#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sqlite3.h>

static NSString *const kChromeCookieErrorDomain = @"TrailBrowser.ChromeCookieImporter";

static const double kWindowsEpochToUnixSeconds = 11644473600.0;

@implementation ChromeProfile
@end

@implementation ChromeCookieImportResult
@end

@implementation ChromeCookieImporter

#pragma mark - Filesystem layout

+ (nullable NSString *)chromeUserDataDirectory {
    NSString *home = NSHomeDirectory();
    NSString *path = [home stringByAppendingPathComponent:
                      @"Library/Application Support/Google/Chrome"];
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
        return path;
    }
    return nil;
}

+ (BOOL)isChromeInstalled {
    return [self chromeUserDataDirectory] != nil;
}

+ (nullable NSString *)cookiesPathForProfileDirectory:(NSString *)directory {
    NSString *root = [self chromeUserDataDirectory];
    if (!root) return nil;

    NSString *profileRoot = [root stringByAppendingPathComponent:directory];
    NSArray<NSString *> *candidates = @[
        [profileRoot stringByAppendingPathComponent:@"Network/Cookies"],
        [profileRoot stringByAppendingPathComponent:@"Cookies"],
    ];
    for (NSString *candidate in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

#pragma mark - Profiles

+ (NSArray<ChromeProfile *> *)availableProfiles {
    NSString *root = [self chromeUserDataDirectory];
    if (!root) return @[];

    NSDictionary *infoCache = nil;
    NSData *localState = [NSData dataWithContentsOfFile:
                          [root stringByAppendingPathComponent:@"Local State"]];
    if (localState) {
        NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:localState
                                                              options:0
                                                                error:NULL];
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            NSDictionary *profile = parsed[@"profile"];
            if ([profile isKindOfClass:[NSDictionary class]] &&
                [profile[@"info_cache"] isKindOfClass:[NSDictionary class]]) {
                infoCache = profile[@"info_cache"];
            }
        }
    }

    NSArray<NSString *> *entries = [[NSFileManager defaultManager]
                                    contentsOfDirectoryAtPath:root error:NULL] ?: @[];
    NSMutableArray<ChromeProfile *> *profiles = [NSMutableArray array];

    for (NSString *entry in entries) {
        BOOL looksLikeProfile = [entry isEqualToString:@"Default"] ||
                                [entry hasPrefix:@"Profile "];
        if (!looksLikeProfile) continue;
        if (![self cookiesPathForProfileDirectory:entry]) continue;

        NSDictionary *cache = infoCache[entry];
        NSString *name = nil;
        NSString *email = nil;
        if ([cache isKindOfClass:[NSDictionary class]]) {
            name = [cache[@"name"] isKindOfClass:[NSString class]] ? cache[@"name"] : nil;
            email = [cache[@"user_name"] isKindOfClass:[NSString class]] ? cache[@"user_name"] : nil;
        }

        ChromeProfile *profile = [[ChromeProfile alloc] init];
        profile.directory = entry;
        profile.displayName = name.length ? name : entry;
        profile.email = email.length ? email : nil;
        [profiles addObject:profile];
    }

    [profiles sortUsingComparator:^NSComparisonResult(ChromeProfile *a, ChromeProfile *b) {
        if ([a.directory isEqualToString:@"Default"]) return NSOrderedAscending;
        if ([b.directory isEqualToString:@"Default"]) return NSOrderedDescending;
        return [a.directory compare:b.directory options:NSNumericSearch];
    }];

    return profiles;
}

#pragma mark - Decryption key

+ (nullable NSData *)decryptionKeyWithError:(NSError **)error {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"Chrome Safe Storage",
        (__bridge id)kSecAttrAccount: @"Chrome",
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };

    CFTypeRef raw = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &raw);
    if (status != errSecSuccess || raw == NULL) {
        if (error) {
            NSString *message;
            if (status == errSecItemNotFound) {
                message = @"No \"Chrome Safe Storage\" key found in the Keychain. "
                           "Is Google Chrome installed?";
            } else if (status == errSecUserCanceled || status == errSecAuthFailed) {
                message = @"Keychain access for \"Chrome Safe Storage\" was denied.";
            } else {
                NSString *detail = (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL);
                message = [NSString stringWithFormat:
                           @"Could not read the Chrome Safe Storage key (%d): %@",
                           (int)status, detail ?: @"unknown error"];
            }
            *error = [NSError errorWithDomain:kChromeCookieErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    NSData *password = (__bridge_transfer NSData *)raw;

    unsigned char derived[kCCKeySizeAES128];
    const char *salt = "saltysalt";
    int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      password.bytes, password.length,
                                      (const uint8_t *)salt, strlen(salt),
                                      kCCPRFHmacAlgSHA1, 1003,
                                      derived, sizeof(derived));
    if (result != kCCSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:kChromeCookieErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Failed to derive the Chrome cookie key."}];
        }
        return nil;
    }

    return [NSData dataWithBytes:derived length:sizeof(derived)];
}

+ (nullable NSData *)decryptData:(NSData *)encrypted
                         withKey:(NSData *)key
                   schemaVersion:(int)schemaVersion {
    if (encrypted.length <= 3) return nil;

    const unsigned char *bytes = encrypted.bytes;
    if (!(bytes[0] == 'v' && (bytes[1] == '1') && (bytes[2] == '0' || bytes[2] == '1'))) {
        return nil;
    }

    NSData *cipher = [encrypted subdataWithRange:NSMakeRange(3, encrypted.length - 3)];
    if (cipher.length == 0 || (cipher.length % kCCBlockSizeAES128) != 0) return nil;

    unsigned char iv[kCCBlockSizeAES128];
    memset(iv, ' ', sizeof(iv));

    size_t bufferSize = cipher.length + kCCBlockSizeAES128;
    NSMutableData *plain = [NSMutableData dataWithLength:bufferSize];
    size_t decryptedLength = 0;

    CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                     key.bytes, key.length,
                                     iv,
                                     cipher.bytes, cipher.length,
                                     plain.mutableBytes, bufferSize, &decryptedLength);
    if (status != kCCSuccess) return nil;
    plain.length = decryptedLength;

    if (schemaVersion >= 24 && plain.length > 32) {
        return [plain subdataWithRange:NSMakeRange(32, plain.length - 32)];
    }

    return plain;
}

+ (nullable NSString *)decryptValue:(NSData *)encrypted
                             withKey:(NSData *)key
                       schemaVersion:(int)schemaVersion {
    NSData *plain = [self decryptData:encrypted withKey:key schemaVersion:schemaVersion];
    if (!plain) return nil;

    NSString *value = [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
    return value ?: [[NSString alloc] initWithData:plain encoding:NSISOLatin1StringEncoding];
}

+ (nullable NSString *)temporaryCopyOfCookiesDatabase:(NSString *)cookiesPath
                                            directory:(NSString **)tempDirectory
                                                error:(NSError **)error {
    NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"TrailBrowser-Cookies-%@",
                           [[NSUUID UUID] UUIDString]]];
    NSError *createError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:tempRoot
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&createError]) {
        if (error) {
            *error = [NSError errorWithDomain:kChromeCookieErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:
                                                     @"Could not create a temporary cookie import directory: %@",
                                                     createError.localizedDescription ?: @"unknown error"]}];
        }
        return nil;
    }

    NSString *copyPath = [tempRoot stringByAppendingPathComponent:@"Cookies"];
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:cookiesPath toPath:copyPath error:&copyError]) {
        [[NSFileManager defaultManager] removeItemAtPath:tempRoot error:NULL];
        if (error) {
            *error = [NSError errorWithDomain:kChromeCookieErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:
                                                     @"Could not read the Chrome cookies database: %@",
                                                     copyError.localizedDescription ?: @"unknown error"]}];
        }
        return nil;
    }

    for (NSString *suffix in @[ @"-wal", @"-shm" ]) {
        NSString *sidecar = [cookiesPath stringByAppendingString:suffix];
        if (![[NSFileManager defaultManager] fileExistsAtPath:sidecar]) continue;
        NSString *sidecarCopy = [copyPath stringByAppendingString:suffix];
        [[NSFileManager defaultManager] copyItemAtPath:sidecar toPath:sidecarCopy error:NULL];
    }

    if (tempDirectory) *tempDirectory = tempRoot;
    return copyPath;
}

+ (int)schemaVersionForDatabase:(sqlite3 *)db {
    sqlite3_stmt *stmt = NULL;
    int version = 0;
    if (sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) version = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    return version;
}

+ (BOOL)table:(NSString *)table hasColumn:(NSString *)column inDatabase:(sqlite3 *)db {
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(%@)", table];
    sqlite3_stmt *stmt = NULL;
    BOOL found = NO;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSString *name = [self stringFromColumn:1 of:stmt];
            if ([name isEqualToString:column]) {
                found = YES;
                break;
            }
        }
    }
    sqlite3_finalize(stmt);
    return found;
}

#pragma mark - Extraction

+ (nullable NSArray<NSHTTPCookie *> *)cookiesForProfileDirectory:(NSString *)directory
                                                          error:(NSError **)error {
    return [self cookiesForProfileDirectory:directory error:error importResult:nil];
}

+ (nullable NSArray<NSHTTPCookie *> *)cookiesForProfileDirectory:(NSString *)directory
                                                          error:(NSError **)error
                                                   importResult:(nullable ChromeCookieImportResult *)result {
    NSString *cookiesPath = [self cookiesPathForProfileDirectory:directory];
    if (!cookiesPath) {
        if (error) {
            *error = [NSError errorWithDomain:kChromeCookieErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"No cookies database found for this Chrome profile."}];
        }
        return nil;
    }

    NSData *key = [self decryptionKeyWithError:error];
    if (!key) return nil;

    NSString *tempDirectory = nil;
    NSString *tempPath = [self temporaryCopyOfCookiesDatabase:cookiesPath
                                                    directory:&tempDirectory
                                                        error:error];
    if (!tempPath) return nil;

    sqlite3 *db = NULL;
    NSMutableArray<NSHTTPCookie *> *cookies = [NSMutableArray array];

    int rc = sqlite3_open_v2(tempPath.fileSystemRepresentation, &db,
                             SQLITE_OPEN_READWRITE, NULL);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        [[NSFileManager defaultManager] removeItemAtPath:tempDirectory error:NULL];
        if (error) {
            *error = [NSError errorWithDomain:kChromeCookieErrorDomain
                                         code:rc
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Could not open the Chrome cookies database."}];
        }
        return nil;
    }

    int schemaVersion = [self schemaVersionForDatabase:db];
    BOOL hasExpiresColumn = [self table:@"cookies" hasColumn:@"has_expires" inDatabase:db];
    BOOL hasPersistentColumn = [self table:@"cookies" hasColumn:@"is_persistent" inDatabase:db];
    NSString *sqlString = (hasExpiresColumn && hasPersistentColumn)
        ? @"SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, has_expires, is_persistent FROM cookies"
        : @"SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite FROM cookies";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sqlString.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        sqlite3_close(db);
        [[NSFileManager defaultManager] removeItemAtPath:tempDirectory error:NULL];
        if (error) {
            *error = [NSError errorWithDomain:kChromeCookieErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Could not query the Chrome cookies database."}];
        }
        return nil;
    }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSString *host = [self stringFromColumn:0 of:stmt];
        NSString *name = [self stringFromColumn:1 of:stmt];
        NSString *plainValue = [self stringFromColumn:2 of:stmt];
        NSString *path = [self stringFromColumn:4 of:stmt];
        long long expiresUtc = sqlite3_column_int64(stmt, 5);
        BOOL isSecure = sqlite3_column_int(stmt, 6) != 0;
        BOOL isHTTPOnly = sqlite3_column_int(stmt, 7) != 0;
        int sameSite = sqlite3_column_int(stmt, 8);
        BOOL hasExpires = hasExpiresColumn ? (sqlite3_column_int(stmt, 9) != 0) : (expiresUtc > 0);
        BOOL isPersistent = hasPersistentColumn ? (sqlite3_column_int(stmt, 10) != 0) : hasExpires;

        if (host.length == 0 || name.length == 0) {
            result.skipped += 1;
            continue;
        }

        NSString *value = nil;
        BOOL encryptedValueFailed = NO;
        const void *blob = sqlite3_column_blob(stmt, 3);
        int blobLength = sqlite3_column_bytes(stmt, 3);
        if (blob && blobLength > 0) {
            NSData *encrypted = [NSData dataWithBytes:blob length:blobLength];
            value = [self decryptValue:encrypted withKey:key schemaVersion:schemaVersion];
            encryptedValueFailed = (value == nil);
        }
        if (value == nil) value = plainValue;
        if (value == nil || (encryptedValueFailed && plainValue.length == 0)) {
            result.skipped += 1;
            if (encryptedValueFailed) result.decryptionFailures += 1;
            continue;
        }

        NSHTTPCookie *cookie = [self cookieWithHost:host
                                               name:name
                                              value:value
                                               path:path
                                         expiresUtc:expiresUtc
                                         hasExpires:hasExpires
                                         persistent:isPersistent
                                             secure:isSecure
                                           httpOnly:isHTTPOnly
                                           sameSite:sameSite];
        if (cookie) {
            [cookies addObject:cookie];
        } else {
            result.skipped += 1;
        }
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    [[NSFileManager defaultManager] removeItemAtPath:tempDirectory error:NULL];

    return cookies;
}

+ (nullable NSString *)stringFromColumn:(int)column of:(sqlite3_stmt *)stmt {
    const unsigned char *text = sqlite3_column_text(stmt, column);
    if (!text) return nil;
    int length = sqlite3_column_bytes(stmt, column);
    NSData *data = [NSData dataWithBytes:text length:(NSUInteger)length];
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return value ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

#pragma mark - Cookie construction

+ (nullable NSHTTPCookie *)cookieWithHost:(NSString *)host
                                     name:(NSString *)name
                                    value:(NSString *)value
                                     path:(nullable NSString *)path
                               expiresUtc:(long long)expiresUtc
                               hasExpires:(BOOL)hasExpires
                                persistent:(BOOL)persistent
                                   secure:(BOOL)secure
                                 httpOnly:(BOOL)httpOnly
                                 sameSite:(int)sameSite {
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    properties[NSHTTPCookieName] = name;
    properties[NSHTTPCookieValue] = value;
    properties[NSHTTPCookieDomain] = host;
    properties[NSHTTPCookiePath] = path.length ? path : @"/";
    properties[NSHTTPCookieVersion] = @"0";
    properties[NSHTTPCookieDiscard] = persistent ? @"FALSE" : @"TRUE";
    if (secure) properties[NSHTTPCookieSecure] = @"TRUE";
    if (httpOnly) properties[@"HttpOnly"] = @YES;

    if (hasExpires && persistent && expiresUtc > 0) {
        double unixSeconds = (double)expiresUtc / 1000000.0 - kWindowsEpochToUnixSeconds;
        if (unixSeconds <= [[NSDate date] timeIntervalSince1970]) return nil;
        properties[NSHTTPCookieExpires] = [NSDate dateWithTimeIntervalSince1970:unixSeconds];
    }

    if (@available(macOS 10.15, *)) {
        if (sameSite == 0) {
            properties[NSHTTPCookieSameSitePolicy] = @"none";
        } else if (sameSite == 1) {
            properties[NSHTTPCookieSameSitePolicy] = NSHTTPCookieSameSiteLax;
        } else if (sameSite == 2) {
            properties[NSHTTPCookieSameSitePolicy] = NSHTTPCookieSameSiteStrict;
        }
    }

    return [NSHTTPCookie cookieWithProperties:properties];
}

#pragma mark - Import

+ (void)importProfileDirectory:(NSString *)directory
               intoCookieStore:(WKHTTPCookieStore *)store
                    completion:(void (^)(ChromeCookieImportResult *_Nullable,
                                         NSError *_Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        ChromeCookieImportResult *result = [[ChromeCookieImportResult alloc] init];
        NSArray<NSHTTPCookie *> *cookies = [self cookiesForProfileDirectory:directory
                                                                       error:&error
                                                                importResult:result];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (cookies == nil) {
                completion(nil, error);
                return;
            }

            if (cookies.count == 0) {
                completion(result, nil);
                return;
            }

            __block NSUInteger remaining = cookies.count;
            for (NSHTTPCookie *cookie in cookies) {
                [store setCookie:cookie completionHandler:^{
                    result.imported += 1;
                    if (--remaining == 0) {
                        completion(result, nil);
                    }
                }];
            }
        });
    });
}

@end
