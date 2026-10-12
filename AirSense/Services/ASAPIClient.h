#pragma clang diagnostic ignored "-Wnullability-completeness"

// ASAPIClient.h — The single place that talks to the ESP32 REST API and to Firebase.
// Every call in API.md is represented here; nothing else in the app builds URLs.

#import <Foundation/Foundation.h>
#import "Models/ASModels.h"
#import "Models/ASHistory.h"

typedef void (^ASResultBlock)(id _Nullable result, NSError * _Nullable error);

/// Out-parameter result block for calls whose success value is "no payload" (POST led/buzzer…).
typedef void (^ASEmptyBlock)(NSError * _Nullable error);

@interface ASAPIClient : NSObject

/// Base URL derived from the user-entered host, e.g. "192.168.1.100" or "192.168.1.100:8080"
/// -> http://192.168.1.100/api/…
+ (NSURL *)baseURLFromHost:(NSString *)host;

- (instancetype)initWithBaseURL:(NSURL * _Nullable)baseURL;
@property (nonatomic, strong, readonly) NSURL *baseURL;
@property (nonatomic, assign, readonly) NSTimeInterval timeout;

/// GET /api/data
- (void)fetchSnapshotWithCompletion:(void (^)(ASSnapshot * _Nullable snap, NSError * _Nullable err))completion;

/// GET /api/mq — all three gas sensors.
- (void)fetchGasWithCompletion:(void (^)(ASGasReading * _Nullable reading, NSError * _Nullable err))completion;

/// GET /api/mq/{key} — one sensor; a bad key is a server 404.
- (void)fetchGasSensorForKey:(NSString *)key
                  completion:(void (^)(ASGasSensor * _Nullable sensor, NSError * _Nullable err))completion;

/// POST /api/led?state=on|off|auto
- (void)setLedState:(NSString *)state completion:(ASEmptyBlock)completion;

/// POST /api/buzzer?state=on|off|auto
- (void)setBuzzerState:(NSString *)state completion:(ASEmptyBlock)completion;

/// POST /api/fan?state=on|off|auto
- (void)setFanState:(NSString *)state completion:(ASEmptyBlock)completion;

/// GET /api/calibrate — current R0 and clean air ratios for all 3 MQ sensors.
- (void)fetchCalibrationWithCompletion:(void (^)(NSDictionary * _Nullable info, NSError * _Nullable err))completion;

/// POST /api/calibrate?samples=N — recalibrate R0 in clean air (samples default 50).
- (void)calibrateSensorsWithSamples:(NSInteger)samples
                         completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable err))completion;

/// GET /api/firebase
- (void)fetchFirebaseStateWithCompletion:(void (^)(ASFirebaseState * _Nullable state, NSError * _Nullable err))completion;

/// POST /api/firebase?state=on|off  ("auto" is rejected by the firmware with 400)
- (void)setFirebaseState:(NSString *)state completion:(ASEmptyBlock)completion;

/// POST /api/threshold?key=…&value=…
- (void)setThresholdForKey:(NSString *)key
                     value:(double)value
                completion:(ASEmptyBlock)completion;

#pragma mark - Firebase Realtime Database (history source)

/// esp32/database URL + auth secret, supplied by Settings and held in the Keychain.
/// The ESP itself never exposes these — they are the app's own credentials.
@property (nonatomic, copy) NSString *firebaseDatabaseURL;
@property (nonatomic, copy) NSString *firebaseSecret;

/// GET <db>/esp32/history.json?auth=<secret>&orderBy="$key"&limitToLast=<n>
/// The firmware pushes one node every firebase.interval_ms; at 30s a 30-day window is
/// ~86,000 nodes, so the read is windowed to the requested range.
/// Returns samples in chronological order; an empty array when the tree is empty.
- (void)fetchFirebaseHistoryForRange:(ASRange)range
                  espIntervalSeconds:(NSTimeInterval)espIntervalSeconds
                           completion:(void (^)(NSArray<ASSample *> * _Nullable samples,
                                                NSUInteger truncatedCount,
                                                NSError * _Nullable err))completion;

/// GET <db>/esp32/latest.json?auth=<secret>
- (void)fetchFirebaseLatestWithCompletion:(void (^)(ASSnapshot * _Nullable snap, NSError * _Nullable err))completion;

@end

#pragma mark - Errors

extern NSString * const ASErrorDomain;

typedef NS_ENUM(NSInteger, ASErrorCode) {
    ASErrorCodeOffline = -1009,     // mirrors NSURLErrorNotConnectedToInternet
    ASErrorCodeTimeout = -1001,
    ASErrorCodeBadURL  = -1998,
    ASErrorCodeHTTP    = -1997,     // server answered with 4xx/5xx; userInfo holds the message
    ASErrorCodeEmptyResponse = -1996,
    ASErrorCodeInvalidJSON = -1995,
    ASErrorCodeNotConfigured = -1994,   // no host entered yet
    ASErrorCodeAuth      = -1993,   // 401/403 from Firebase
};

/// Key under which the server-provided message is stored in NSError.userInfo.
extern NSString * const ASErrorUserInfoMessageKey;

/// Turns a transport/URL error into something safe to show a user — never a raw error text.
NSString * ASFriendlyErrorMessage(NSError *error);

/// "Cập nhật 2 phút trước" / "Vừa xong"
NSString * ASRelativeTimeString(NSDate * _Nullable date);
NSString * ASShortTimeString(NSDate *date);
NSString * ASShortDateTimeString(NSDate *date);
NSString * ASShortDayString(NSDate *date);
/// Uptime in ms -> "2d 4h 13m"
NSString * ASUptimeString(double ms);