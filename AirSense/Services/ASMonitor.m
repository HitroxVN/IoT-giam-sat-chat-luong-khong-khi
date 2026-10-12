#import "Services/ASMonitor.h"
#import "Services/ASSettings.h"
#import "Services/ASNotificationManager.h"
#import "Models/ASModels.h"

NSString * const ASMonitorDidUpdateNotification = @"ASMonitorDidUpdate";
NSString * const ASMonitorDidReachabilityChangeNotification = @"ASMonitorDidReachabilityChange";

@implementation ASMonitor {
    NSTimer *_timer;
    BOOL _pollInFlight;
    BOOL _gasInFlight;
}

+ (ASMonitor *)shared
{
    static ASMonitor *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [[ASMonitor alloc] init]; });
    return m;
}

- (instancetype)init
{
    if ((self = [super init])) {
        ASSettings *cfg = [ASSettings shared];
        _client = [[ASAPIClient alloc] initWithBaseURL:cfg.espBaseURL];
        [cfg applyToClient:_client];
        _historyStore = [[ASHistoryStore alloc] initWithBasePath:cfg.historyPath];
        [_historyStore load:NULL];
        _reachability = ASReachabilityUnknown;
    }
    return self;
}

#pragma mark - Observation

- (void)notifyObservers
{
    if (NSThread.isMainThread) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASMonitorDidUpdateNotification object:self];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ASMonitorDidUpdateNotification object:self];
        });
    }
}

- (void)notifyReachability
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ASMonitorDidReachabilityChangeNotification object:self];
    });
}

- (void)applySnapshot:(ASSnapshot *)snap fromFirebase:(BOOL)fromFirebase
{
    _snapshot = snap;
    _snapshotFromFirebase = fromFirebase;
    if (!fromFirebase) _lastError = nil;
    [[ASNotificationManager shared] evaluateSnapshot:snap];
    [self notifyObservers];
}

#pragma mark - Polling

- (void)refresh
{
    if (_pollInFlight) return;             // never stack requests
    if (![ASSettings shared].isConfigured) {
        _lastError = [NSError errorWithDomain:ASErrorDomain code:ASErrorCodeNotConfigured
                                     userInfo:@{NSLocalizedDescriptionKey: @"Chưa nhập IP của ESP32.",
                                                ASErrorUserInfoMessageKey: @"Chưa nhập IP của ESP32. Vào Cài đặt để thêm."}];
        [self notifyObservers];
        return;
    }

    // Rebuild the client if the host changed since the last call.
    ASSettings *cfg = [ASSettings shared];
    if (![cfg.espBaseURL isEqual:self.client.baseURL]) {
        _client = [[ASAPIClient alloc] initWithBaseURL:cfg.espBaseURL];
        [cfg applyToClient:_client];
    }

    _pollInFlight = YES;
    _loading = YES;
    [self notifyObservers];

    __weak typeof(self) weakSelf = self;
    [self.client fetchSnapshotWithCompletion:^(ASSnapshot *snap, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        strongSelf->_pollInFlight = NO;
        strongSelf->_loading = NO;

        if (err) {
            strongSelf->_lastError = err;
            if (strongSelf.reachability != ASReachabilityOffline) {
                strongSelf->_reachability = ASReachabilityOffline;
                [strongSelf notifyReachability];
            }
        } else {
            if (strongSelf->_reachability != ASReachabilityOnline) {
                strongSelf->_reachability = ASReachabilityOnline;
                [strongSelf notifyReachability];
            }
            [strongSelf applySnapshot:snap fromFirebase:NO];
            [strongSelf recordLocalSample];
        }
        [strongSelf notifyObservers];
    }];
}

- (void)refreshGasSensors
{
    if (_gasInFlight || ![ASSettings shared].isConfigured) return;
    _gasInFlight = YES;

    __weak typeof(self) weakSelf = self;
    [self.client fetchGasWithCompletion:^(ASGasReading *reading, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        strongSelf->_gasInFlight = NO;
        // Gas detail is supplementary: a failure here must not clobber the main snapshot error.
        if (err == nil) {
            strongSelf->_gasReading = reading;
            [strongSelf notifyObservers];
        }
    }];
}

- (void)startPolling
{
    [self stopPolling];
    NSInteger interval = [ASSettings shared].refreshInterval;
    if (interval <= 0) return;
    _timer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                              target:self
                                            selector:@selector(refresh)
                                            userInfo:nil
                                             repeats:YES];
    // Keeps scrolling and animations smooth while the timer fires.
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stopPolling
{
    [_timer invalidate];
    _timer = nil;
}

- (void)dealloc
{
    [_timer invalidate];
}

#pragma mark - Commands

- (void)setLedState:(NSString *)state completion:(ASEmptyBlock)completion
{
    __weak typeof(self) weakSelf = self;
    [self.client setLedState:state completion:^(NSError *err) {
        if (err == nil) [weakSelf refresh];
        completion(err);
    }];
}

- (void)setBuzzerState:(NSString *)state completion:(ASEmptyBlock)completion
{
    __weak typeof(self) weakSelf = self;
    [self.client setBuzzerState:state completion:^(NSError *err) {
        if (err == nil) [weakSelf refresh];
        completion(err);
    }];
}

- (void)setFanState:(NSString *)state completion:(ASEmptyBlock)completion
{
    __weak typeof(self) weakSelf = self;
    [self.client setFanState:state completion:^(NSError *err) {
        if (err == nil) [weakSelf refresh];
        completion(err);
    }];
}

- (void)calibrateSensorsWithSamples:(NSInteger)samples
                         completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable err))completion
{
    __weak typeof(self) weakSelf = self;
    [self.client calibrateSensorsWithSamples:samples completion:^(NSDictionary *result, NSError *err) {
        if (err == nil) {
            [weakSelf refresh];
            [weakSelf refreshGasSensors];
        }
        completion(result, err);
    }];
}

- (void)setFirebaseState:(NSString *)state completion:(ASEmptyBlock)completion
{
    __weak typeof(self) weakSelf = self;
    [self.client setFirebaseState:state completion:^(NSError *err) {
        if (err == nil) [weakSelf refresh];
        completion(err);
    }];
}

- (void)setThresholdForKey:(NSString *)key value:(double)value completion:(ASEmptyBlock)completion
{
    __weak typeof(self) weakSelf = self;
    [self.client setThresholdForKey:key value:value completion:^(NSError *err) {
        if (err == nil) [weakSelf refresh];
        completion(err);
    }];
}

#pragma mark - Derived

- (BOOL)recordLocalSample
{
    ASSnapshot *s = self.snapshot;
    if (s == nil || self.snapshotFromFirebase) return NO;

    ASSample *sample = [[ASSample alloc] init];
    sample.date = s.receivedAt ?: [NSDate date];
    sample.pm25 = s.pm25.hasValue ? s.pm25.value.doubleValue : NAN;
    for (ASReading *r in s.readings) {
        if (!r.hasValue) continue;
        double v = r.value.doubleValue;
        if (r.kind == ASSensorKindPM10)     sample.pm10 = v;
        else if (r.kind == ASSensorKindCO2) sample.co2 = v;
        else if (r.kind == ASSensorKindLPG) sample.lpg = v;
        else if (r.kind == ASSensorKindCO)  sample.co = v;
        else if (r.kind == ASSensorKindTemp) sample.temp = v;
        else if (r.kind == ASSensorKindHumidity) sample.humidity = v;
    }
    sample.aqi = s.aqi;

    if (![self.historyStore appendSample:sample]) return NO;
    // Persist at most once per poll cycle; the file is rewritten wholesale.
    [self.historyStore save:NULL];
    return YES;
}

- (BOOL)isStale
{
    if (self.snapshot == nil) return NO;
    if (self.snapshotFromFirebase) return YES;
    if (self.reachability == ASReachabilityOffline) return YES;
    return -self.snapshot.receivedAt.timeIntervalSinceNow > 180.0;   // 3 missed cycles
}

- (NSString *)staleSinceDescription
{
    if (self.snapshot == nil) return @"";
    if (self.snapshotFromFirebase) return @"Nguồn: Firebase esp32/latest";
    return [NSString stringWithFormat:@"Cập nhật %@", ASRelativeTimeString(self.snapshot.receivedAt)];
}

@end