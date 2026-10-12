#import <Foundation/Foundation.h>
#import "Models/ASModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ASNotificationManager : NSObject

@property (class, nonatomic, readonly) ASNotificationManager *shared;

/// Request user permission for notifications if not yet granted.
- (void)requestAuthorizationWithCompletion:(void (^ _Nullable)(BOOL granted))completion;

/// Evaluates state transition on every new snapshot and dispatches local notification if needed.
- (void)evaluateSnapshot:(ASSnapshot * _Nullable)snapshot;

/// Reset tracked states (e.g. when changing devices).
- (void)resetTrackedState;

@end

NS_ASSUME_NONNULL_END
