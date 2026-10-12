#import "Services/ASAPIClient.h"
#import "Utils/ASJSON.h"

NSString * const ASErrorDomain = @"com.airsense.monitor.error";
NSString * const ASErrorUserInfoMessageKey = @"ASErrorMessage";

/// Upper bound on one Firebase history read. 86,400 = exactly 30 days at the default 30s push.
static const NSUInteger kASFirebaseMaxNodes = 86400;

@implementation ASAPIClient {
    NSURLSession *_session;
    dispatch_queue_t _fbQueue;   // serialises Firebase reads so one screen can't flood the DB
}

#pragma mark - URL helpers

/// Accepts "192.168.1.100", "192.168.1.100:8080", "http://host", "https://host".
/// Returns nil for anything that is not a usable host — no scheme-less garbage reaches NSURL.
+ (NSURL *)baseURLFromHost:(NSString *)host
{
    NSString *h = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (h.length == 0) return nil;

    if ([h hasPrefix:@"http://"] || [h hasPrefix:@"https://"]) {
        NSURL *u = [NSURL URLWithString:h];
        return u.host.length ? u : nil;
    }

    // Strip a stray path the user may have pasted.
    NSString *hostPart = h;
    NSRange slash = [h rangeOfString:@"/"];
    if (slash.location != NSNotFound) hostPart = [h substringToIndex:slash.location];

    NSString *scheme = [h hasPrefix:@"https"] ? @"https" : @"http";
    if (![hostPart containsString:@"://"]) {
        NSString *full = [NSString stringWithFormat:@"%@://%@", scheme, hostPart];
        NSURL *u = [NSURL URLWithString:full];
        return u.host.length ? u : nil;
    }
    return nil;
}

static NSString *ASPercentEscape(NSString *s)
{
    return [s stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
}

#pragma mark - ASAPIClient


- (instancetype)initWithBaseURL:(NSURL *)baseURL
{
    if ((self = [super init])) {
        _baseURL = baseURL;
        _timeout = 8.0;
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = _timeout;
        cfg.timeoutIntervalForResource = _timeout * 2;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:cfg];
        _fbQueue = dispatch_queue_create("com.airsense.firebase", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSError *)notConfiguredError
{
    return [NSError errorWithDomain:ASErrorDomain
                               code:ASErrorCodeNotConfigured
                           userInfo:@{NSLocalizedDescriptionKey: @"Chưa cấu hình địa chỉ ESP32.",
                                       ASErrorUserInfoMessageKey: @"Chưa nhập IP của ESP32. Vào Cài đặt để thêm."}];
}

- (NSURL *)urlForPath:(NSString *)path query:(NSString *)query
{
    NSString *base = self.baseURL.absoluteString;
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSString *full = [NSString stringWithFormat:@"%@%@%@", base, path, query.length ? query : @""];
    return [NSURL URLWithString:full];
}

- (NSError *)errorForTransport:(NSError *)err
{
    NSInteger code = err.code;
    NSString *msg;
    if (code == NSURLErrorNotConnectedToInternet) {
        code = ASErrorCodeOffline;
        msg = @"Không có kết nối mạng. Kiểm tra Wi-Fi và địa chỉ IP của ESP32.";
    } else if (code == NSURLErrorTimedOut) {
        code = ASErrorCodeTimeout;
        msg = @"Máy chủ phản hồi quá chậm. ESP32 có thể đang bận hoặc đã mất kết nối Wi-Fi.";
    } else if (code == NSURLErrorCannotFindHost || code == NSURLErrorCannotConnectToHost) {
        code = ASErrorCodeOffline;
        msg = @"Không kết nối được tới ESP32. IP có thể đã thay đổi sau lần khởi động lại.";
    } else {
        msg = @"Không thể kết nối tới máy chủ. Kiểm tra địa chỉ IP trong Cài đặt.";
    }
    return [NSError errorWithDomain:ASErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg, ASErrorUserInfoMessageKey: msg}];
}

/// Core request. `completion` always runs on the main queue.
- (void)performRequestWithMethod:(NSString *)method
                             path:(NSString *)path
                           query:(NSString *)query
                            host:(NSString *)hostOverride
                      completion:(void (^)(id _Nullable json, NSInteger status, NSError * _Nullable err))completion
{
    if (hostOverride == nil && self.baseURL == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, 0, [self notConfiguredError]); });
        return;
    }

    NSURL *url;
    if (hostOverride) {
        NSURLComponents *c = [NSURLComponents componentsWithString:hostOverride];
        c.path = path;
        c.query = query.length ? query : nil;
        url = c.URL;
    } else {
        url = [self urlForPath:path query:query];
    }
    if (url == nil) {
        NSError *e = [NSError errorWithDomain:ASErrorDomain code:ASErrorCodeBadURL
                                    userInfo:@{NSLocalizedDescriptionKey: @"Địa chỉ không hợp lệ.",
                                                ASErrorUserInfoMessageKey: @"Địa chỉ máy chủ không hợp lệ. Kiểm tra lại trong Cài đặt."}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, 0, e); });
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    req.timeoutInterval = self.timeout;
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [_session dataTaskWithRequest:req
                                            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error) {
            NSError *mapped = [self errorForTransport:error];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, 0, mapped); });
            return;
        }

        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];

        if (data.length == 0) {
            if (status >= 200 && status < 300) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, status, nil); });
            } else {
                NSString *msg = ASExtractError(nil, status);
                NSError *e = [NSError errorWithDomain:ASErrorDomain code:ASErrorCodeHTTP
                                            userInfo:@{NSLocalizedDescriptionKey: msg, ASErrorUserInfoMessageKey: msg}];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, status, e); });
            }
            return;
        }

        id obj = nil;
        NSError *parseErr = nil;
        if ([data isKindOfClass:[NSData class]]) {
            obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseErr];
        }

        if (status < 200 || status >= 300) {
            NSDictionary *body = [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
            NSString *msg = ASExtractError(body, status);
            NSInteger code = (status == 401 || status == 403) ? ASErrorCodeAuth : ASErrorCodeHTTP;
            NSError *e = [NSError errorWithDomain:ASErrorDomain code:code
                                        userInfo:@{NSLocalizedDescriptionKey: msg, ASErrorUserInfoMessageKey: msg}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, status, e); });
            return;
        }

        if (obj == nil) {
            NSString *msg = @"Máy chủ trả về dữ liệu không đọc được.";
            NSError *e = [NSError errorWithDomain:ASErrorDomain code:ASErrorCodeInvalidJSON
                                        userInfo:@{NSLocalizedDescriptionKey: msg, ASErrorUserInfoMessageKey: msg}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, status, e); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{ completion(obj, status, nil); });
    }];
    [task resume];
}

#pragma mark - API.md endpoints

- (void)fetchSnapshotWithCompletion:(void (^)(ASSnapshot * _Nullable, NSError * _Nullable))completion
{
    [self performRequestWithMethod:@"GET" path:@"/api/data" query:nil host:nil
                       completion:^(id json, NSInteger status, NSError *err) {
        completion(err ? nil : ASParseSnapshot(json), err);
    }];
}

- (void)fetchGasWithCompletion:(void (^)(ASGasReading * _Nullable, NSError * _Nullable))completion
{
    [self performRequestWithMethod:@"GET" path:@"/api/mq" query:nil host:nil
                       completion:^(id json, NSInteger status, NSError *err) {
        completion(err ? nil : ASParseGasReading(json), err);
    }];
}

- (void)fetchGasSensorForKey:(NSString *)key
                   completion:(void (^)(ASGasSensor * _Nullable, NSError * _Nullable))completion
{
    NSString *path = [NSString stringWithFormat:@"/api/mq/%@", ASPercentEscape(key)];
    [self performRequestWithMethod:@"GET" path:path query:nil host:nil
                       completion:^(id json, NSInteger status, NSError *err) {
        if (err) { completion(nil, err); return; }
        ASGasSensor *s = ASParseGasSensor(json);
        if (s == nil || (s.adc == nil && s.ppm == nil && s.r0 == nil)) {
            ASGasReading *g = ASParseGasReading(json);
            s = g.sensors.firstObject;
        }
        if (s == nil) {
            NSString *msg = @"Không đọc được dữ liệu cảm biến.";
            completion(nil, [NSError errorWithDomain:ASErrorDomain code:ASErrorCodeInvalidJSON
                                            userInfo:@{NSLocalizedDescriptionKey: msg, ASErrorUserInfoMessageKey: msg}]);
            return;
        }
        if (s.key.length == 0) s.key = key;
        completion(s, nil);
    }];
}

- (void)postState:(NSString *)state to:(NSString *)path completion:(ASEmptyBlock)completion
{
    NSString *q = [NSString stringWithFormat:@"?state=%@", ASPercentEscape(state)];
    [self performRequestWithMethod:@"POST" path:path query:q host:nil
                       completion:^(id json, NSInteger status, NSError *err) {
        completion(err);
    }];
}

- (void)setLedState:(NSString *)state completion:(ASEmptyBlock)completion    { [self postState:state to:@"/api/led" completion:completion]; }
- (void)setBuzzerState:(NSString *)state completion:(ASEmptyBlock)completion { [self postState:state to:@"/api/buzzer" completion:completion]; }
- (void)setFanState:(NSString *)state completion:(ASEmptyBlock)completion    { [self postState:state to:@"/api/fan" completion:completion]; }

- (void)fetchCalibrationWithCompletion:(void (^)(NSDictionary * _Nullable info, NSError * _Nullable err))completion
{
    [self performRequestWithMethod:@"GET" path:@"/api/calibrate" query:nil host:nil
                       completion:^(id json, NSInteger status, NSError *err) {
        if (err) { completion(nil, err); return; }
        completion([json isKindOfClass:[NSDictionary class]] ? json : nil, nil);
    }];
}

- (void)calibrateSensorsWithSamples:(NSInteger)samples
                         completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable err))completion
{
    NSInteger count = samples > 0 ? samples : 30; // default 30 samples
    NSString *q = [NSString stringWithFormat:@"?samples=%ld", (long)count];
    [self performRequestWithMethod:@"POST" path:@"/api/calibrate" query:q host:nil
                       completion:^(id json, NSInteger status, NSError *err) {
        if (err) { completion(nil, err); return; }
        completion([json isKindOfClass:[NSDictionary class]] ? json : nil, nil);
    }];
}

- (void)fetchFirebaseStateWithCompletion:(void (^)(ASFirebaseState * _Nullable, NSError * _Nullable))completion
{
    [self performRequestWithMethod:@"GET" path:@"/api/firebase" query:nil host:nil
                       completion:^(id json, NSInteger status, NSError *err) {
        if (err) { completion(nil, err); return; }
        ASFirebaseState *f = [[ASFirebaseState alloc] init];
        f.enabled    = ASDictBool(json, @"enabled", NO);
        f.lastCode   = ASDictNumber(json, @"last_code") ?: @0;
        f.intervalMs = ASDictNumber(json, @"interval_ms") ?: @0;
        completion(f, nil);
    }];
}

- (void)setFirebaseState:(NSString *)state completion:(ASEmptyBlock)completion
{
    [self postState:state to:@"/api/firebase" completion:completion];
}

- (void)setThresholdForKey:(NSString *)key value:(double)value completion:(ASEmptyBlock)completion
{
    NSString *q = [NSString stringWithFormat:@"?key=%@&value=%@",
                   ASPercentEscape(key), ASTrimNumber(value)];
    [self performRequestWithMethod:@"POST" path:@"/api/threshold" query:q host:nil
                       completion:^(id json, NSInteger status, NSError *err) { completion(err); }];
}

#pragma mark - Firebase Realtime Database

- (void)firebaseRequestPath:(NSString *)path
                     query:(NSString *)query
                completion:(void (^)(id _Nullable json, NSError * _Nullable err))completion
{
    // Serialised: the History screen can fire several range reads and we must not
    // stampede the database.
    dispatch_async(_fbQueue, ^{
        [self performRequestWithMethod:@"GET" path:path query:query host:self.firebaseDatabaseURL
                           completion:^(id json, NSInteger status, NSError *err) {
            completion(json, err);
        }];
    });
}

- (void)fetchFirebaseHistoryForRange:(ASRange)range
                  espIntervalSeconds:(NSTimeInterval)espIntervalSeconds
                           completion:(void (^)(NSArray<ASSample *> * _Nullable, NSUInteger, NSError * _Nullable))completion
{
    if (self.firebaseSecret.length == 0 || self.firebaseDatabaseURL.length == 0) {
        NSString *msg = @"Chưa cấu hình Firebase. Thêm Database URL và secret trong Cài đặt để xem lịch sử.";
        completion(nil, 0, [NSError errorWithDomain:ASErrorDomain code:ASErrorCodeNotConfigured
                                          userInfo:@{NSLocalizedDescriptionKey: msg, ASErrorUserInfoMessageKey: msg}]);
        return;
    }

    NSTimeInterval step = espIntervalSeconds > 0 ? espIntervalSeconds : 30.0;
    NSUInteger want = (NSUInteger)ceil(ASRangeSeconds(range) / step);
    // Firebase caps a single REST read; a larger window is approximated by coarser
    // sampling rather than an unbounded multi-page scan.
    if (want > kASFirebaseMaxNodes) want = kASFirebaseMaxNodes;
    if (want < 2) want = 2;

    NSString *q = [NSString stringWithFormat:@"auth=%@&orderBy=%%22$key%%22&limitToLast=%lu",
                   ASPercentEscape(self.firebaseSecret), (unsigned long)want];

    [self firebaseRequestPath:@"/esp32/history.json" query:q
                   completion:^(id json, NSError *err) {
        if (err) { completion(nil, 0, err); return; }
        if (![json isKindOfClass:[NSDictionary class]]) { completion(@[], 0, nil); return; }

        NSDictionary *dict = json;
        NSUInteger stored = dict.count;
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-ASRangeSeconds(range)];
        NSArray<ASSample *> *samples = ASParseFirebaseHistory(dict, step, [NSDate date], cutoff);
        completion(samples, stored > want ? stored - want : 0, nil);
    }];
}

- (void)fetchFirebaseLatestWithCompletion:(void (^)(ASSnapshot * _Nullable, NSError * _Nullable))completion
{
    if (self.firebaseSecret.length == 0 || self.firebaseDatabaseURL.length == 0) {
        NSString *msg = @"Chưa cấu hình Firebase. Thêm Database URL và secret trong Cài đặt.";
        completion(nil, [NSError errorWithDomain:ASErrorDomain code:ASErrorCodeNotConfigured
                                        userInfo:@{NSLocalizedDescriptionKey: msg, ASErrorUserInfoMessageKey: msg}]);
        return;
    }
    [self firebaseRequestPath:@"/esp32/latest.json"
                        query:[NSString stringWithFormat:@"auth=%@", ASPercentEscape(self.firebaseSecret)]
                   completion:^(id json, NSError *err) {
        completion(err ? nil : ASParseSnapshot(json), err);
    }];
}

#pragma mark - Message helpers

NSString *ASFriendlyErrorMessage(NSError *error)
{
    if (error == nil) return @"Đã xảy ra lỗi.";
    NSString *custom = error.userInfo[ASErrorUserInfoMessageKey];
    if (custom.length) return custom;
    return @"Đã xảy ra lỗi. Vui lòng thử lại.";
}

NSString *ASRelativeTimeString(NSDate *date)
{
    if (date == nil) return @"Chưa có dữ liệu";
    NSTimeInterval dt = -[date timeIntervalSinceNow];
    if (dt < 0) dt = 0;
    if (dt < 45)    return @"Vừa xong";
    if (dt < 3600)  return [NSString stringWithFormat:@"%.0f phút trước", dt / 60.0];
    if (dt < 86400) return [NSString stringWithFormat:@"%.0f giờ trước", dt / 3600.0];
    return [NSString stringWithFormat:@"%.0f ngày trước", dt / 86400.0];
}

static NSDateFormatter *ASFormatterWithTemplate(NSString *fmt)
{
    static NSMutableDictionary<NSString *, NSDateFormatter *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    @synchronized (cache) {
        NSDateFormatter *f = cache[fmt];
        if (f == nil) {
            f = [[NSDateFormatter alloc] init];
            f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            f.dateFormat = fmt;
            cache[fmt] = f;
        }
        return f;
    }
}

NSString *ASShortTimeString(NSDate *date)
{
    if (date == nil) return @"--:--";
    return [ASFormatterWithTemplate(@"HH:mm") stringFromDate:date];
}

NSString *ASShortDateTimeString(NSDate *date)
{
    if (date == nil) return @"--";
    return [ASFormatterWithTemplate(@"dd/MM HH:mm") stringFromDate:date];
}

NSString *ASShortDayString(NSDate *date)
{
    if (date == nil) return @"--";
    return [ASFormatterWithTemplate(@"dd/MM") stringFromDate:date];
}

NSString *ASUptimeString(double ms)
{
    if (isnan(ms) || ms < 0) return @"—";
    long long total = (long long)(ms / 1000.0);
    long long d = total / 86400;
    long long h = (total % 86400) / 3600;
    long long m = (total % 3600) / 60;
    if (d > 0) return [NSString stringWithFormat:@"%lld ngày %lld giờ", d, h];
    if (h > 0) return [NSString stringWithFormat:@"%lld giờ %lld phút", h, m];
    return [NSString stringWithFormat:@"%lld phút", m];
}
@end
