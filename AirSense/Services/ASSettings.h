#pragma clang diagnostic ignored "-Wnullability-completeness"

// ASSettings.h — App configuration.
// The Firebase secret is a credential, so it lives in the Keychain (kSecClassGenericPassword,
// ThisDeviceOnly). Non-sensitive values sit in NSUserDefaults.

#import <Foundation/Foundation.h>
#import "Services/ASAPIClient.h"

@interface ASSettings : NSObject

@property (class, nonatomic, readonly) ASSettings *shared;

/// ESP32 address, e.g. "192.168.1.100". Empty until the user sets it.
@property (nonatomic, copy) NSString *espHost;
@property (nonatomic, readonly) NSURL *espBaseURL;
@property (nonatomic, readonly) BOOL isConfigured;

/// Firebase Realtime Database URL, e.g. "https://my-db.firebaseio.com".
/// Not a credential on its own, so it lives in defaults.
@property (nonatomic, copy) NSString *firebaseDatabaseURL;

/// Firebase database secret — Keychain only, never NSUserDefaults.
@property (nonatomic, copy) NSString *firebaseSecret;

@property (nonatomic, readonly) BOOL firebaseConfigured;

typedef NS_ENUM(NSInteger, ASAppearance) {
    ASAppearanceSystem = 0,
    ASAppearanceLight  = 1,
    ASAppearanceDark   = 2,
};

/// Follows the system unless the user overrides it here.
@property (nonatomic, assign) ASAppearance appearanceMode;
@property (nonatomic, readonly) BOOL appearanceIsDark;

/// Auto-refresh interval in seconds. 0 disables the poll timer.
@property (nonatomic, assign) NSInteger refreshInterval;
@property (nonatomic, copy) NSString *deviceName;

/// Notification preferences
@property (nonatomic, assign) BOOL notificationsEnabled;
@property (nonatomic, assign) BOOL notifyWarning;
@property (nonatomic, assign) BOOL notifyAQI;

/// Path of the locally recorded sample log (Documents/samples.jsonl).
@property (nonatomic, readonly) NSString *historyPath;

- (void)resetDeviceSettings;

/// Wires the client's Firebase credentials from current settings.
- (void)applyToClient:(ASAPIClient *)client;

@end

/// Minimal generic-password Keychain wrapper. No dependency, no logging of secrets.
@interface ASKeychain : NSObject
+ (BOOL)setString:(NSString * _Nullable)value forKey:(NSString *)key;
+ (NSString * _Nullable)stringForKey:(NSString *)key;
+ (BOOL)deleteStringForKey:(NSString *)key;
@end