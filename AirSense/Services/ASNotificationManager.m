#import "Services/ASNotificationManager.h"
#import "Services/ASSettings.h"
#import "Utils/ASJSON.h"
#import <UserNotifications/UserNotifications.h>

@interface ASNotificationManager () <UNUserNotificationCenterDelegate>
@property (nonatomic, assign) BOOL hasPreviousState;
@property (nonatomic, assign) BOOL previousDanger;
@property (nonatomic, copy)   NSString *previousAlertLevel;
@property (nonatomic, assign) ASAQILevel previousAQILevel;
@end

@implementation ASNotificationManager

+ (ASNotificationManager *)shared
{
    static ASNotificationManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ASNotificationManager alloc] init]; });
    return s;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _hasPreviousState = NO;
        _previousDanger = NO;
        _previousAlertLevel = @"safe";
        _previousAQILevel = ASAQILevelUnknown;

        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = self;
    }
    return self;
}

- (void)requestAuthorizationWithCompletion:(void (^)(BOOL granted))completion
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    [center requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(granted);
            });
        }
    }];
}

- (void)resetTrackedState
{
    _hasPreviousState = NO;
    _previousDanger = NO;
    _previousAlertLevel = @"safe";
    _previousAQILevel = ASAQILevelUnknown;
}

- (void)evaluateSnapshot:(ASSnapshot *)snap
{
    if (snap == nil) return;

    ASSettings *settings = [ASSettings shared];
    if (!settings.notificationsEnabled) {
        // Update tracked state so when re-enabled we don't fire stale diffs
        _previousDanger = snap.alert.danger;
        _previousAlertLevel = snap.alert.level ?: @"safe";
        _previousAQILevel = snap.aqiLevel;
        _hasPreviousState = YES;
        return;
    }

    BOOL currentDanger = snap.alert.danger;
    NSString *currentLevel = snap.alert.level ?: (currentDanger ? @"danger" : @"safe");
    ASAQILevel currentAQILevel = snap.aqiLevel;

    // First snapshot received: seed the state and only alert if already in danger
    if (!_hasPreviousState) {
        _hasPreviousState = YES;
        _previousDanger = currentDanger;
        _previousAlertLevel = currentLevel;
        _previousAQILevel = currentAQILevel;

        if (currentDanger) {
            [self sendDangerNotificationWithSnapshot:snap];
        }
        return;
    }

    // 1. Safe/Warning -> Danger (Khẩn cấp)
    if (!_previousDanger && currentDanger) {
        [self sendDangerNotificationWithSnapshot:snap];
    }
    // 2. Danger/Warning -> Safe (Trở lại an toàn)
    else if ((_previousDanger || [_previousAlertLevel isEqualToString:@"warning"]) &&
             !currentDanger && [currentLevel isEqualToString:@"safe"]) {
        [self sendSafeRestoredNotification];
    }
    // 3. Safe -> Warning (Cảnh báo tiềm ẩn, >= 80% ngưỡng)
    else if (settings.notifyWarning &&
             [_previousAlertLevel isEqualToString:@"safe"] &&
             [currentLevel isEqualToString:@"warning"] && !currentDanger) {
        [self sendWarningNotificationWithSnapshot:snap];
    }

    // 4. AQI Category ухудшилась (Chuyển sang mức Kém / Xấu / Rất xấu / Nguy hại)
    if (settings.notifyAQI && currentAQILevel != ASAQILevelUnknown) {
        if (_previousAQILevel != ASAQILevelUnknown && currentAQILevel > _previousAQILevel && currentAQILevel >= ASAQILevelSensitive) {
            [self sendAQIDegradedNotificationWithSnapshot:snap];
        }
    }

    // Save states for next cycle
    _previousDanger = currentDanger;
    _previousAlertLevel = currentLevel;
    _previousAQILevel = currentAQILevel;
}

#pragma mark - Notification Senders

- (void)sendDangerNotificationWithSnapshot:(ASSnapshot *)snap
{
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"CẢNH BÁO NGUY HIỂM!";
    
    // Find tripped sensors for detailed message
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    for (ASReading *r in snap.alert.tripped) {
        if (r.hasValue) {
            [details addObject:[NSString stringWithFormat:@"%@: %@ %@", r.label, ASTrimNumber(r.value.doubleValue), r.unit]];
        }
    }

    if (details.count > 0) {
        content.body = [NSString stringWithFormat:@"Nồng độ vượt ngưỡng nguy hại (%@). Quạt và còi cảnh báo đã kích hoạt!",
                        [details componentsJoinedByString:@", "]];
    } else {
        content.body = @"Chỉ số không khí vượt ngưỡng nguy hại cài đặt. Quạt và còi cảnh báo đã kích hoạt!";
    }

    content.sound = [UNNotificationSound defaultCriticalSound];
    [self scheduleImmediateNotification:content identifier:@"airsense.alert.danger"];
}

- (void)sendWarningNotificationWithSnapshot:(ASSnapshot *)snap
{
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Cảnh báo chất lượng không khí";

    ASReading *worst = snap.worst;
    if (worst && worst.hasValue) {
        content.body = [NSString stringWithFormat:@"Chỉ số %@ chạm mức %ld%% ngưỡng cài đặt (%@ %@). Hãy chú ý thông gió.",
                        worst.label, (long)lround(worst.ratio * 100), ASTrimNumber(worst.value.doubleValue), worst.unit];
    } else {
        content.body = @"Một số chỉ số đang tiến gần đến ngưỡng cảnh báo (≥ 80%). Hãy chú ý mở cửa hoặc thông gió.";
    }

    content.sound = [UNNotificationSound defaultSound];
    [self scheduleImmediateNotification:content identifier:@"airsense.alert.warning"];
}

- (void)sendSafeRestoredNotification
{
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Không khí đã an toàn trở lại";
    content.body = @"Các chỉ số ô nhiễm đã hạ dưới ngưỡng cho phép. Còi và quạt đã tắt.";
    content.sound = [UNNotificationSound defaultSound];
    [self scheduleImmediateNotification:content identifier:@"airsense.alert.safe"];
}

- (void)sendAQIDegradedNotificationWithSnapshot:(ASSnapshot *)snap
{
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [NSString stringWithFormat:@"Chất lượng không khí chuyển mức %@", ASAQILevelName(snap.aqiLevel)];
    
    if (!isnan(snap.aqi)) {
        content.body = [NSString stringWithFormat:@"Chỉ số AQI hiện tại là %@ (%@). %@",
                        ASTrimNumber(snap.aqi), ASAQILevelName(snap.aqiLevel),
                        ASAQILevelDescription(snap.aqiLevel)];
    } else {
        content.body = [NSString stringWithFormat:@"Chất lượng không khí đang ở mức %@. %@",
                        ASAQILevelName(snap.aqiLevel), ASAQILevelDescription(snap.aqiLevel)];
    }

    content.sound = [UNNotificationSound defaultSound];
    [self scheduleImmediateNotification:content identifier:@"airsense.aqi.degraded"];
}

- (void)scheduleImmediateNotification:(UNNotificationContent *)content identifier:(NSString *)identifier
{
    // Deliver in 1 second to avoid potential race conditions with system presentation
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
    NSString *uniqueID = [NSString stringWithFormat:@"%@.%f", identifier, [[NSDate date] timeIntervalSince1970]];
    UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:uniqueID content:content trigger:trigger];

    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AirSense] Failed to schedule notification: %@", error);
        }
    }];
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
    // Present banner and play sound even when app is active in foreground
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge);
}

@end
