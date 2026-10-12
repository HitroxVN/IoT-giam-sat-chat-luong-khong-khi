#pragma clang diagnostic ignored "-Wnullability-completeness"

// ASMonitor.h — Single source of truth for device state.
// Owns the poll timer, the last good snapshot, the last error, and reachability.
// View controllers observe; they never call the API directly.

#import <Foundation/Foundation.h>
#import "Services/ASAPIClient.h"
#import "Models/ASHistory.h"

typedef NS_ENUM(NSInteger, ASReachability) {
    ASReachabilityUnknown = 0,
    ASReachabilityOnline,
    ASReachabilityOffline,
};

extern NSString * const ASMonitorDidUpdateNotification;   // object = ASMonitor
extern NSString * const ASMonitorDidReachabilityChangeNotification;

@interface ASMonitor : NSObject

@property (class, nonatomic, readonly) ASMonitor *shared;

@property (nonatomic, readonly) ASAPIClient *client;
@property (nonatomic, readonly) ASHistoryStore *historyStore;

/// Most recent successful GET /api/data. Stays populated while offline so the UI can
/// keep showing it, flagged as stale.
@property (nonatomic, strong, readonly) ASSnapshot * _Nullable snapshot;
@property (nonatomic, strong, readonly) ASGasReading * _Nullable gasReading;
@property (nonatomic, strong, readonly) NSError * _Nullable lastError;
@property (nonatomic, assign, readonly) ASReachability reachability;
@property (nonatomic, assign, readonly) BOOL loading;
/// YES when `snapshot` came from the Firebase `latest` mirror rather than a direct ESP read.
@property (nonatomic, assign, readonly) BOOL snapshotFromFirebase;

/// YES once a poll has failed and no direct read has succeeded since.
@property (nonatomic, readonly) BOOL isStale;
@property (nonatomic, readonly) NSString *staleSinceDescription;

/// Fires one GET /api/data. Safe to call from pull-to-refresh; ignores overlapping polls.
- (void)refresh;

/// Fires one GET /api/mq (all sensors). Fire-and-forget; updates `gasReading` on success.
- (void)refreshGasSensors;

- (void)startPolling;
- (void)stopPolling;

/// Applies a POST result: on success the state is re-read from the device rather than
/// assumed, because the firmware reports actual pin state, not the requested mode.
- (void)setLedState:(NSString *)state completion:(ASEmptyBlock)completion;
- (void)setBuzzerState:(NSString *)state completion:(ASEmptyBlock)completion;
- (void)setFanState:(NSString *)state completion:(ASEmptyBlock)completion;
- (void)setFirebaseState:(NSString *)state completion:(ASEmptyBlock)completion;
- (void)setThresholdForKey:(NSString *)key value:(double)value completion:(ASEmptyBlock)completion;
- (void)calibrateSensorsWithSamples:(NSInteger)samples
                         completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable err))completion;

/// Records the current snapshot into the local sample log so History has data even
/// without Firebase. Returns NO when nothing was appended.
- (BOOL)recordLocalSample;

@end