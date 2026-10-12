#import "Models/ASModels.h"
#import "Utils/ASJSON.h"

#pragma mark - AQI levels

const double kASAQIPM25CleanCutoff = 9.0;    // ug/m3 — 24h PM2.5 below this is reported on a 0-50 scale
const double kASAQIPM25TopCutoff  = 325.4;  // ug/m3 — formula ceiling; above it the sub-index is undefined

ASLevelName ASAQILevelName(ASAQILevel lvl)
{
    switch (lvl) {
        case ASAQILevelGood:        return @"Tốt";
        case ASAQILevelModerate:    return @"Trung bình";
        case ASAQILevelSensitive:   return @"Kém";
        case ASAQILevelUnhealthy:   return @"Xấu";
        case ASAQILevelVeryUnhealthy:return @"Rất xấu";
        case ASAQILevelHazardous:   return @"Nguy hại";
        case ASAQILevelUnknown:     break;
    }
    return @"Không rõ";
}

ASAQILevel ASAQILevelForCategory(NSString *category)
{
    if (category == nil || ![category isKindOfClass:[NSString class]]) return ASAQILevelUnknown;
    NSString *c = [category stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if ([c isEqualToString:@"tốt"] || [c isEqualToString:@"tot"] || [c isEqualToString:@"good"]) return ASAQILevelGood;
    if ([c isEqualToString:@"trung bình"] || [c isEqualToString:@"trung binh"] || [c isEqualToString:@"moderate"]) return ASAQILevelModerate;
    if ([c isEqualToString:@"kém"] || [c isEqualToString:@"kem"] || [c isEqualToString:@"ảnh hưởng nhạy cảm"] || [c isEqualToString:@"nhạy cảm"] || [c isEqualToString:@"sensitive"]) return ASAQILevelSensitive;
    if ([c isEqualToString:@"xấu"] || [c isEqualToString:@"xau"] || [c isEqualToString:@"không lành mạnh"] || [c isEqualToString:@"unhealthy"]) return ASAQILevelUnhealthy;
    if ([c isEqualToString:@"rất xấu"] || [c isEqualToString:@"rat xau"] || [c isEqualToString:@"very unhealthy"]) return ASAQILevelVeryUnhealthy;
    if ([c isEqualToString:@"nguy hại"] || [c isEqualToString:@"nguy hai"] || [c isEqualToString:@"hazardous"]) return ASAQILevelHazardous;
    return ASAQILevelUnknown;
}

ASLevelName ASAQILevelDescription(ASAQILevel lvl)
{
    switch (lvl) {
        case ASAQILevelGood:
            return @"Chất lượng không khí đạt mức tốt. Không cần thao tác nào.";
        case ASAQILevelModerate:
            return @"Chất lượng chấp nhận được. Người nhạy cảm nên giảm thời gian ở ngoài trời.";
        case ASAQILevelSensitive:
            return @"Người bị hen, dị ứng, bệnh tim mạch hoặc trẻ em nên hạn chế hoạt động ngoài trời.";
        case ASAQILevelUnhealthy:
            return @"Mọi người nên giảm hoạt động ngoài trời, đặc biệt là tập thể dục.";
        case ASAQILevelVeryUnhealthy:
            return @"Tránh ra ngoài. Nếu bắt buộc, hãy đeo khẩu trang lọc bụi mịn.";
        case ASAQILevelHazardous:
            return @"Nguy hại. Ở lại trong nhà, đóng cửa sổ và chạy máy lọc nếu có.";
        case ASAQILevelUnknown:
            break;
    }
    return @"Chưa đủ dữ liệu PM2.5 hợp lệ để đánh giá.";
}

ASLevelName ASAQILevelShortLabel(ASAQILevel lvl)
{
    switch (lvl) {
        case ASAQILevelGood:          return @"Bình thường";
        case ASAQILevelModerate:      return @"Cần theo dõi";
        case ASAQILevelSensitive:     return @"Nhạy cảm";
        case ASAQILevelUnhealthy:     return @"Cảnh báo";
        case ASAQILevelVeryUnhealthy: return @"Nguy hiểm";
        case ASAQILevelHazardous:     return @"Nguy hại";
        case ASAQILevelUnknown:       return @"Không rõ";
    }
    return @"Không rõ";
}

double ASAQIFromPM25(double pm25)
{
    if (isnan(pm25) || pm25 < 0.0) return NAN;
    // The EPA table truncates the 24h concentration to 0.1 ug/m3 before breakpoint lookup.
    double c = floor(pm25 * 10.0) / 10.0;

    if (c > kASAQIPM25TopCutoff) return NAN;

    if (c <= 4.4)  return ASClampDouble(50.0  * c / 4.4, 0, 500);
    if (c <= 9.4)  return ASClampDouble(50.0  + 49.0  * (c - 4.5)  / 5.0,  0, 500);
    if (c <= 12.4) return ASClampDouble(100.0 + 49.0  * (c - 9.5)  / 3.0,  0, 500);
    if (c <= 35.4) return ASClampDouble(150.0 + 49.0  * (c - 12.5) / 23.0,  0, 500);
    if (c <= 55.4) return ASClampDouble(200.0 + 49.0  * (c - 35.5) / 20.0,  0, 500);
    if (c <= 150.4) return ASClampDouble(300.0 + 49.0 * (c - 55.5) / 95.0,  0, 500);
    if (c <= 250.4) return ASClampDouble(400.0 + 49.0 * (c - 150.5) / 100.0, 0, 500);
    return ASClampDouble(500.0 + 49.0 * (c - 250.5) / 75.0, 0, 500);
}

BOOL ASAQIPM25RangeForAQI(double aqi, double *outLow, double *outHigh)
{
    if (isnan(aqi) || aqi < 0 || aqi > 500) return NO;
    double lo, hi;
    if (aqi <= 50)      { lo = 0.0;  hi = 4.4;  }
    else if (aqi <= 100) { lo = 4.5;  hi = 9.4;  }
    else if (aqi <= 150) { lo = 9.5;  hi = 12.4; }
    else if (aqi <= 200) { lo = 12.5; hi = 35.4; }
    else if (aqi <= 300) { lo = 35.5; hi = 55.4; }
    else if (aqi <= 400) { lo = 55.5; hi = 150.4; }
    else if (aqi <= 500) { lo = 150.5; hi = 250.4; }
    else                 return NO;

    // Invert the linear segment the AQI landed in.
    double cLo, cHi, spanLo, spanHi, base;
    if (aqi <= 50)      { cLo = 0.0;  cHi = 4.4;  spanLo = 0;   spanHi = 50;  base = 0;   }
    else if (aqi <= 100) { cLo = 4.5;  cHi = 9.4;  spanLo = 51;  spanHi = 100; base = 50;  }
    else if (aqi <= 150) { cLo = 9.5;  cHi = 12.4; spanLo = 101; spanHi = 150; base = 100; }
    else if (aqi <= 200) { cLo = 12.5; cHi = 35.4; spanLo = 151; spanHi = 200; base = 150; }
    else if (aqi <= 300) { cLo = 35.5; cHi = 55.4; spanLo = 201; spanHi = 300; base = 200; }
    else if (aqi <= 400) { cLo = 55.5; cHi = 150.4; spanLo = 301, spanHi = 400; base = 300; }
    else                 { cLo = 150.5; cHi = 250.4; spanLo = 401, spanHi = 500; base = 400; }

    if (outLow)  *outLow  = cLo + (cHi - cLo) * (aqi - spanLo) / (spanHi - spanLo);
    if (outHigh) *outHigh = hi;
    return YES;
}

ASAQILevel ASAQILevelForValue(double aqi)
{
    if (isnan(aqi)) return ASAQILevelUnknown;
    if (aqi <= 50)  return ASAQILevelGood;
    if (aqi <= 100) return ASAQILevelModerate;
    if (aqi <= 150) return ASAQILevelSensitive;
    if (aqi <= 200) return ASAQILevelUnhealthy;
    if (aqi <= 300) return ASAQILevelVeryUnhealthy;
    return ASAQILevelHazardous;
}

ASAQILevel ASAQILevelForMetric(double value, double threshold)
{
    if (isnan(value) || isnan(threshold) || threshold <= 0) return ASAQILevelUnknown;
    double r = value / threshold;
    if (r < 0.5)  return ASAQILevelGood;
    if (r < 0.8)  return ASAQILevelModerate;
    if (r < 1.0)  return ASAQILevelSensitive;
    if (r < 1.5)  return ASAQILevelUnhealthy;
    if (r < 2.0)  return ASAQILevelVeryUnhealthy;
    return ASAQILevelHazardous;
}

double ASAQISeverityFraction(double aqi)
{
    if (isnan(aqi) || aqi < 0) return 0;
    return ASClampDouble(aqi / 500.0, 0, 1);
}

#pragma mark - ASReading

@implementation ASReading

- (instancetype)init
{
    if ((self = [super init])) {
        _key = @"";
        _label = @"";
        _symbol = @"circle.dotted";
        _unit = @"";
        _note = @"";
        _threshold = NAN;
    }
    return self;
}

- (BOOL)hasValue       { return self.value != nil && !isnan(self.value.doubleValue); }
- (BOOL)alerts         { return self.hasValue && !isnan(self.threshold) && self.threshold > 0 && self.value.doubleValue >= self.threshold; }
- (double)ratio        { return (self.hasValue && self.threshold > 0) ? self.value.doubleValue / self.threshold : 0.0; }

- (ASAQILevel)level
{
    if (self.kind == ASSensorKindTemp || self.kind == ASSensorKindHumidity) return ASAQILevelUnknown;
    if (!self.hasValue) return ASAQILevelUnknown;
    if (isnan(self.threshold) || self.threshold <= 0) return ASAQILevelUnknown;
    return ASAQILevelForMetric(self.value.doubleValue, self.threshold);
}

@end

#pragma mark - ASGasSensor

@implementation ASGasSensor

- (instancetype)init
{
    if ((self = [super init])) { _key = @""; _gas = @""; }
    return self;
}

- (BOOL)negative      { return self.ppm != nil && self.ppm.doubleValue < 0; }
- (double)adcFraction { return ASClampDouble(self.adc.doubleValue / 4095.0, 0, 1); }

@end

#pragma mark - ASGasReading

@implementation ASGasReading

- (instancetype)init
{
    if ((self = [super init])) { _sensors = @[]; }
    return self;
}

- (ASGasSensor *)sensorForKey:(NSString *)key
{
    for (ASGasSensor *s in self.sensors) if ([s.key isEqualToString:key]) return s;
    return nil;
}

@end

#pragma mark - Simple state holders

@implementation ASAlert
- (instancetype)init { if ((self = [super init])) { _level = @"safe"; _tripped = @[]; } return self; }
@end

@implementation ASFirebaseState
- (instancetype)init
{
    if ((self = [super init])) { _lastCode = @0; _intervalMs = @0; }
    return self;
}
@end

@implementation ASThresholds
- (instancetype)init
{
    if ((self = [super init])) { _co2 = NAN; _lpg = NAN; _co = NAN; _pm25 = NAN; _pm10 = NAN; }
    return self;
}
@end

#pragma mark - ASSnapshot

@implementation ASSnapshot

- (instancetype)init
{
    if ((self = [super init])) {
        _device = @"";
        _ssid = @"";
        _readings = @[];
        _thresholds = [[ASThresholds alloc] init];
        _alert = [[ASAlert alloc] init];
        _firebase = [[ASFirebaseState alloc] init];
    }
    return self;
}

- (ASReading *)pm25
{
    for (ASReading *r in self.readings) if (r.kind == ASSensorKindPM25) return r;
    return nil;
}

- (ASReading *)co2
{
    for (ASReading *r in self.readings) if (r.kind == ASSensorKindCO2) return r;
    return nil;
}

- (double)aqi
{
    // Prioritize authoritative AQI value from API ("aqi": { "value": ... })
    if (self.aqiValue != nil && ![self.aqiValue isEqual:[NSNull null]]) {
        double v = self.aqiValue.doubleValue;
        if (!isnan(v) && v >= 0) return v;
    }
    // Fallback: derive from PM2.5 if dust sensor is valid
    if (!self.dustValid) return NAN;
    ASReading *p = self.pm25;
    if (!p.hasValue) return NAN;
    return ASAQIFromPM25(p.value.doubleValue);
}

- (ASAQILevel)aqiLevel
{
    // If API provided category ("aqi": { "category": "Kém" }), map it directly
    if (self.aqiCategory.length > 0) {
        ASAQILevel lvl = ASAQILevelForCategory(self.aqiCategory);
        if (lvl != ASAQILevelUnknown) return lvl;
    }
    return ASAQILevelForValue(self.aqi);
}

- (ASReading *)worst
{
    ASReading *best = nil;
    double bestRatio = 0;
    for (ASReading *r in self.readings) {
        if (!r.alerts) continue;
        if (r.ratio > bestRatio) { bestRatio = r.ratio; best = r; }
    }
    return best;
}

@end

#pragma mark - Parsing

/// Maps a threshold key onto the reading kind it drives.
static ASSensorKind ASKindForThresholdKey(NSString *key)
{
    if ([key isEqualToString:@"pm2_5"]) return ASSensorKindPM25;
    if ([key isEqualToString:@"pm10"])  return ASSensorKindPM10;
    if ([key isEqualToString:@"co2"])   return ASSensorKindCO2;
    if ([key isEqualToString:@"lpg"])   return ASSensorKindLPG;
    if ([key isEqualToString:@"co"])    return ASSensorKindCO;
    return ASSensorKindPM25;
}

ASThresholds *ASParseThresholds(NSDictionary *json)
{
    ASThresholds *t = [[ASThresholds alloc] init];
    NSDictionary *src = ASDictDict(json, @"thresholds");
    if (src == nil) return t;   // stays all-NAN -> partial
    t.co2  = ASDictDouble(src, @"co2");
    t.lpg  = ASDictDouble(src, @"lpg");
    t.co   = ASDictDouble(src, @"co");
    t.pm25 = ASDictDouble(src, @"pm2_5");
    t.pm10 = ASDictDouble(src, @"pm10");
    t.partial = isnan(t.co2) || isnan(t.lpg) || isnan(t.co) || isnan(t.pm25) || isnan(t.pm10);
    return t;
}

ASSnapshot *ASParseSnapshot(NSDictionary *json)
{
    ASSnapshot *s = [[ASSnapshot alloc] init];
    s.receivedAt = [NSDate date];
    if (![json isKindOfClass:[NSDictionary class]]) return s;

    s.device   = ASDictString(json, @"device") ?: @"ESP32";
    s.uptimeMs = ASDictNumber(json, @"uptime_ms");

    NSDictionary *wifi = ASDictDict(json, @"wifi");
    s.wifiConnected = ASDictBool(wifi, @"connected", NO);
    s.ssid = ASDictString(wifi, @"ssid") ?: @"";
    s.rssi = ASDictNumber(wifi, @"rssi");

    NSDictionary *env = ASDictDict(json, @"env");
    s.envValid  = ASDictBool(env, @"valid", NO);
    NSNumber *temp = ASDictNumber(env, @"temp_c");

    NSDictionary *dust = ASDictDict(json, @"dust");
    s.dustValid = ASDictBool(dust, @"valid", NO);
    NSNumber *pm25 = ASDictNumber(dust, @"pm2_5");
    NSNumber *pm10 = ASDictNumber(dust, @"pm10");

    NSDictionary *gas = ASDictDict(json, @"gas");

    NSDictionary *aqiDict = ASDictDict(json, @"aqi");
    s.aqiValue    = ASDictNumber(aqiDict, @"value");
    s.aqiCategory = ASDictString(aqiDict, @"category") ?: @"";

    s.thresholds = ASParseThresholds(json);

    NSDictionary *alert = ASDictDict(json, @"alert");
    s.alert.danger   = ASDictBool(alert, @"danger", NO);
    s.alert.level    = ASDictString(alert, @"level") ?: (s.alert.danger ? @"danger" : @"safe");
    s.alert.led      = [ASDictNumber(alert, @"led") integerValue];
    s.alert.buzzer   = [ASDictNumber(alert, @"buzzer") integerValue];
    s.alert.fan      = [ASDictNumber(alert, @"fan") integerValue];

    NSDictionary *fb = ASDictDict(json, @"firebase");
    s.firebase.enabled   = ASDictBool(fb, @"enabled", NO);
    s.firebase.lastCode  = ASDictNumber(fb, @"last_code") ?: @0;
    s.firebase.intervalMs = ASDictNumber(fb, @"interval_ms") ?: @0;

    // Readings in dashboard order. Only fields the ESP actually reports appear here.
    NSMutableArray<ASReading *> *rs = [NSMutableArray array];

    ASReading *r;
    r = [[ASReading alloc] init];
    r.key = @"pm2_5"; r.label = @"PM2.5"; r.symbol = @"aqi.medium";
    r.unit = @"µg/m³"; r.kind = ASSensorKindPM25;
    r.value = s.dustValid ? pm25 : nil;
    r.threshold = s.thresholds.pm25;
    r.note = s.dustValid ? @"" : @"Cảm biến bụi lỗi";
    [rs addObject:r];

    r = [[ASReading alloc] init];
    r.key = @"pm10"; r.label = @"PM10"; r.symbol = @"aqi.high";
    r.unit = @"µg/m³"; r.kind = ASSensorKindPM10;
    r.value = s.dustValid ? pm10 : nil;
    r.threshold = s.thresholds.pm10;
    r.note = @"Tham chiếu — không kích hoạt cảnh báo";
    [rs addObject:r];

    r = [[ASReading alloc] init];
    r.key = @"co2"; r.label = @"CO₂"; r.symbol = @"aqi.low";
    r.unit = @"ppm"; r.kind = ASSensorKindCO2;
    r.value = ASDictNumber(gas, @"co2_ppm");
    r.threshold = s.thresholds.co2;
    [rs addObject:r];

    r = [[ASReading alloc] init];
    r.key = @"lpg"; r.label = @"LPG"; r.symbol = @"flame";
    r.unit = @"ppm"; r.kind = ASSensorKindLPG;
    r.value = ASDictNumber(gas, @"lpg_ppm");
    r.threshold = s.thresholds.lpg;
    [rs addObject:r];

    r = [[ASReading alloc] init];
    r.key = @"co"; r.label = @"CO"; r.symbol = @"smoke";
    r.unit = @"ppm"; r.kind = ASSensorKindCO;
    r.value = ASDictNumber(gas, @"co_ppm");
    r.threshold = s.thresholds.co;
    [rs addObject:r];

    r = [[ASReading alloc] init];
    r.key = @"temp"; r.label = @"Nhiệt độ"; r.symbol = @"thermometer.medium";
    r.unit = @"°C"; r.kind = ASSensorKindTemp;
    r.value = s.envValid ? temp : nil;
    r.threshold = NAN;
    r.note = s.envValid ? @"" : @"Cảm biến môi trường lỗi";
    [rs addObject:r];

    r = [[ASReading alloc] init];
    r.key = @"humidity"; r.label = @"Độ ẩm"; r.symbol = @"humidity";
    r.unit = @"%"; r.kind = ASSensorKindHumidity;
    r.value = s.envValid ? ASDictNumber(env, @"humidity") : nil;
    r.threshold = NAN;
    [rs addObject:r];

    s.readings = rs;

    // alert.danger and alert.level are authoritative; per-metric list shows tripped items.
    NSMutableArray<ASReading *> *tripped = [NSMutableArray array];
    if (s.alert.danger || [s.alert.level isEqualToString:@"warning"] || [s.alert.level isEqualToString:@"danger"]) {
        // API.md: only CO2, LPG, CO and PM2.5 can raise the alert; PM10 is reference.
        for (NSString *k in @[@"co2", @"lpg", @"co", @"pm2_5"]) {
            for (ASReading *rr in rs) if ([rr.key isEqualToString:k] && rr.alerts) [tripped addObject:rr];
        }
    }
    s.alert.tripped = tripped;

    (void)ASKindForThresholdKey;
    return s;
}

ASGasSensor *ASParseGasSensor(NSDictionary *json)
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    ASGasSensor *g = [[ASGasSensor alloc] init];
    g.key    = ASDictString(json, @"key") ?: @"";
    g.gas    = ASDictString(json, @"gas") ?: g.key.uppercaseString;
    g.ppm    = ASDictNumber(json, @"ppm");
    g.adc    = ASDictNumber(json, @"adc");
    g.r0     = ASDictNumber(json, @"r0");
    g.a      = ASDictNumber(json, @"a");
    g.b      = ASDictNumber(json, @"b");
    g.valid  = ASDictBool(json, @"valid", YES);
    return g;
}

ASGasReading *ASParseGasReading(NSDictionary *json)
{
    ASGasReading *out = [[ASGasReading alloc] init];
    if (![json isKindOfClass:[NSDictionary class]]) return out;

    NSArray *arr = ASDictArray(json, @"sensors");
    if (arr != nil) {
        NSMutableArray<ASGasSensor *> *list = [NSMutableArray array];
        for (id item in arr) {
            ASGasSensor *g = ASParseGasSensor(item);
            if (g && g.key.length > 0) [list addObject:g];
        }
        out.sensors = list;
    } else if (json[@"key"] != nil || json[@"adc"] != nil || json[@"ppm"] != nil) {
        // Bare single sensor object from /api/mq/{key}
        ASGasSensor *g = ASParseGasSensor(json);
        if (g) out.sensors = @[g];
    }
    return out;
}

NSString *ASExtractError(NSDictionary *json, NSInteger statusCode)
{
    NSString *msg = ASDictString(json, @"error");
    if (msg.length == 0) {
        switch (statusCode) {
            case 400: msg = @"Tham số không hợp lệ hoặc thiếu."; break;
            case 401: msg = @"Token không hợp lệ hoặc đã hết hạn."; break;
            case 403: msg = @"Database rules chặn ghi."; break;
            case 404: msg = @"Không tìm thấy đường dẫn hoặc khóa."; break;
            default:  msg = @"Máy chủ trả về lỗi."; break;
        }
    }
    return msg;
}

#pragma mark - Advice

ASLevelName ASAQIAdviceHeadline(double aqi, ASAQILevel lvl)
{
    if (lvl == ASAQILevelUnknown) return @"Chưa đánh giá được";
    return [NSString stringWithFormat:@"Chất lượng không khí: %@", ASAQILevelName(lvl)];
}

ASLevelName ASAQIAdviceBody(double aqi, ASAQILevel lvl)
{
    if (lvl == ASAQILevelUnknown) {
        return isnan(aqi)
            ? @"Cảm biến PM2.5 chưa có giá trị hợp lệ, hoặc nồng độ vượt 325,4 µg/m³ — ngoài phạm vi công thức AQI. Không hiển thị chỉ số để tránh báo sai."
            : @"Không đủ dữ liệu để tính AQI.";
    }
    NSMutableString *s = [ASAQILevelDescription(lvl) mutableCopy];

    double lo, hi;
    if (ASAQIPM25RangeForAQI(aqi, &lo, &hi)) {
        [s appendFormat:@"\n\nNgưỡng PM2.5 của mức này: %@ – %@ µg/m³ (nồng độ đo được %@ µg/m³).",
         ASTrimNumber(lo), ASTrimNumber(hi), ASTrimNumber(aqi)];
    }
    return s;
}