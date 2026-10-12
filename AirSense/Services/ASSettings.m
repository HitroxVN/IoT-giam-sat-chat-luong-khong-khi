#import "Services/ASSettings.h"
#import <Security/Security.h>
#import <UIKit/UIKit.h>

static NSString * const kKeychainService = @"com.airsense.monitor";
static NSString * const kKeyFirebaseSecret = @"firebaseSecret";

#pragma mark - Keychain

@implementation ASKeychain

+ (NSMutableDictionary *)baseQueryForKey:(NSString *)key
{
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass]           = (__bridge id)kSecClassGenericPassword;
    q[(__bridge id)kSecAttrService]    = kKeychainService;
    q[(__bridge id)kSecAttrAccount]    = key;
    return q;
}

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key
{
    if (value.length == 0) { return [self deleteStringForKey:key]; }

    NSMutableDictionary *q = [self baseQueryForKey:key];
    SecItemDelete((__bridge CFDictionaryRef)q);

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *add = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:  kKeychainService,
        (__bridge id)kSecAttrAccount:  key,
        (__bridge id)kSecValueData:    data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    };
    OSStatus st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    return st == errSecSuccess;
}

+ (NSString *)stringForKey:(NSString *)key
{
    NSMutableDictionary *q = [self baseQueryForKey:key];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (st != errSecSuccess || out == NULL) { return nil; }

    NSData *data = (__bridge_transfer NSData *)out;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)deleteStringForKey:(NSString *)key
{
    NSMutableDictionary *q = [self baseQueryForKey:key];
    OSStatus st = SecItemDelete((__bridge CFDictionaryRef)q);
    return st == errSecSuccess || st == errSecItemNotFound;
}

@end

#pragma mark - ASSettings

@implementation ASSettings

+ (ASSettings *)shared
{
    static ASSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ASSettings alloc] init]; });
    return s;
}

- (NSString *)espHost
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"espHost"] ?: @"";
}

- (void)setEspHost:(NSString *)v
{
    [[NSUserDefaults standardUserDefaults] setObject:v ?: @"" forKey:@"espHost"];
}

- (NSString *)firebaseDatabaseURL
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"fbHost"] ?: @"";
}

- (void)setFirebaseDatabaseURL:(NSString *)v
{
    [[NSUserDefaults standardUserDefaults] setObject:v ?: @"" forKey:@"fbHost"];
}

- (NSString *)firebaseSecret
{
    return [ASKeychain stringForKey:kKeyFirebaseSecret] ?: @"";
}

- (void)setFirebaseSecret:(NSString *)v
{
    [ASKeychain setString:v forKey:kKeyFirebaseSecret];
}

- (ASAppearance)appearanceMode
{
    NSInteger v = [[NSUserDefaults standardUserDefaults] integerForKey:@"appearanceMode"];
    return (v < ASAppearanceSystem || v > ASAppearanceDark) ? ASAppearanceSystem : (ASAppearance)v;
}

- (void)setAppearanceMode:(ASAppearance)v
{
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"appearanceMode"];
}

- (BOOL)appearanceIsDark
{
    if (self.appearanceMode == ASAppearanceLight) return NO;
    if (self.appearanceMode == 2) return YES;
    return UIUserInterfaceStyleDark;   // 0 == Unspecified
}

- (NSInteger)refreshInterval
{
    NSInteger v = [[NSUserDefaults standardUserDefaults] integerForKey:@"refreshInterval"];
    return v < 0 ? 30 : v;
}

- (void)setRefreshInterval:(NSInteger)v
{
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"refreshInterval"];
}

- (NSString *)deviceName
{
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:@"deviceName"];
    return v.length ? v : @"ESP32 Air Quality";
}

- (void)setDeviceName:(NSString *)v
{
    [[NSUserDefaults standardUserDefaults] setObject:v.length ? v : @"ESP32 Air Quality" forKey:@"deviceName"];
}

- (BOOL)notificationsEnabled
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"notificationsEnabled"] == nil) {
        return YES; // Default to YES
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"notificationsEnabled"];
}

- (void)setNotificationsEnabled:(BOOL)v
{
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"notificationsEnabled"];
}

- (BOOL)notifyWarning
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"notifyWarning"] == nil) {
        return YES; // Default to YES
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"notifyWarning"];
}

- (void)setNotifyWarning:(BOOL)v
{
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"notifyWarning"];
}

- (BOOL)notifyAQI
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"notifyAQI"] == nil) {
        return YES; // Default to YES
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"notifyAQI"];
}

- (void)setNotifyAQI:(BOOL)v
{
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"notifyAQI"];
}

- (NSURL *)espBaseURL
{
    return [ASAPIClient baseURLFromHost:self.espHost];
}

- (BOOL)isConfigured     { return self.espBaseURL != nil; }
- (BOOL)firebaseConfigured { return self.firebaseDatabaseURL.length > 0 && self.firebaseSecret.length > 0; }

- (NSString *)historyPath
{
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = dirs.firstObject ?: NSTemporaryDirectory();
    return [docs stringByAppendingPathComponent:@"samples.jsonl"];
}

- (void)resetDeviceSettings
{
    self.deviceName = @"ESP32 Air Quality";
}

- (void)applyToClient:(ASAPIClient *)client
{
    client.firebaseDatabaseURL = self.firebaseDatabaseURL.length ? self.firebaseDatabaseURL : nil;
    client.firebaseSecret = self.firebaseSecret.length ? self.firebaseSecret : nil;
}

@end