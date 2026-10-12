#import "Models/ASHistory.h"
#import "Models/ASModels.h"
#import "Utils/ASJSON.h"

#pragma mark - Ranges

ASLevelName ASRangeName(ASRange r)
{
    switch (r) {
        case ASRange1H:  return @"1 giờ";
        case ASRange6H:  return @"6 giờ";
        case ASRange24H: return @"24 giờ";
        case ASRange7D:  return @"7 ngày";
        case ASRange30D: return @"30 ngày";
    }
    return @"—";
}

NSTimeInterval ASRangeSeconds(ASRange r)
{
    switch (r) {
        case ASRange1H:  return 3600.0;
        case ASRange6H:  return 6 * 3600.0;
        case ASRange24H: return 24 * 3600.0;
        case ASRange7D:  return 7 * 24 * 3600.0;
        case ASRange30D: return 30 * 24 * 3600.0;
    }
    return 3600.0;
}

NSTimeInterval ASRangeFirebaseFetchSeconds(ASRange r)
{
    switch (r) {
        case ASRange1H:  return 5 * 60.0;
        case ASRange6H:  return 30 * 60.0;
        case ASRange24H: return 3 * 3600.0;
        case ASRange7D:  return 12 * 3600.0;
        case ASRange30D: return 24 * 3600.0;
    }
    return 3600.0;
}

#pragma mark - ASSample

@implementation ASSample

- (instancetype)init
{
    if ((self = [super init])) {
        _pm25 = NAN; _pm10 = NAN; _co2 = NAN; _lpg = NAN; _co = NAN;
        _temp = NAN; _humidity = NAN; _aqi = NAN;
    }
    return self;
}

@end

static double ASDeepDouble(NSDictionary *root, NSString *outer, NSString *inner)
{
    return ASDictDouble(ASDictDict(root, outer), inner);
}

ASSample *ASParseSample(NSDictionary *json)
{
    ASSample *s = [[ASSample alloc] init];
    if (![json isKindOfClass:[NSDictionary class]]) return s;

    // The firmware payload has no timestamp field; the push key supplies the time (see ASExtractFirebaseKeys).
    s.date      = [NSDate date];
    s.pm25      = ASDeepDouble(json, @"dust", @"pm2_5");
    s.pm10      = ASDeepDouble(json, @"dust", @"pm10");
    s.co2       = ASDeepDouble(json, @"gas", @"co2_ppm");
    s.lpg       = ASDeepDouble(json, @"gas", @"lpg_ppm");
    s.co        = ASDeepDouble(json, @"gas", @"co_ppm");
    s.temp      = ASDeepDouble(json, @"env", @"temp_c");
    s.humidity  = ASDeepDouble(json, @"env", @"humidity");
    s.aqi       = ASDeepDouble(json, @"aqi", @"value");

    // A node can be flagged invalid; drop the values rather than plot a misleading zero.
    if (!ASDictBool(ASDictDict(json, @"dust"), @"valid", YES)) { s.pm25 = NAN; s.pm10 = NAN; }
    if (!ASDictBool(ASDictDict(json, @"env"),  @"valid", YES)) { s.temp = NAN; s.humidity = NAN; }
    return s;
}

NSArray<NSString *> *ASExtractFirebaseKeys(NSDictionary *json)
{
    if (![json isKindOfClass:[NSDictionary class]]) return @[];
    return [[json allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

NSArray<ASSample *> *ASParseFirebaseHistory(NSDictionary *json,
                                            NSTimeInterval intervalSeconds,
                                            NSDate *now,
                                            NSDate *cutoff)
{
    NSArray<NSString *> *keys = ASExtractFirebaseKeys(json);
    if (keys.count == 0) return @[];

    NSTimeInterval step = intervalSeconds > 0 ? intervalSeconds : 30.0;
    NSDate *newest = now ?: [NSDate date];

    NSMutableArray<ASSample *> *out = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSUInteger i = 0; i < keys.count; i++) {
        id node = json[keys[i]];
        ASSample *s = ASParseSample(node);
        // Node 0 is the newest; each earlier node is one ESP push interval older.
        NSUInteger back = keys.count - 1 - i;
        s.date = [newest dateByAddingTimeInterval:-(NSTimeInterval)back * step];
        if (cutoff && [s.date compare:cutoff] == NSOrderedAscending) break;   // keys ascend => dates descend
        [out addObject:s];
    }
    return out;
}

double ASSampleValue(ASSample *s, NSString *field)
{
    if (!s || !field) return NAN;
    if ([field isEqualToString:@"pm2_5"])     return s.pm25;
    if ([field isEqualToString:@"pm10"])      return s.pm10;
    if ([field isEqualToString:@"co2"])       return s.co2;
    if ([field isEqualToString:@"lpg"])       return s.lpg;
    if ([field isEqualToString:@"co"])        return s.co;
    if ([field isEqualToString:@"temp"])      return s.temp;
    if ([field isEqualToString:@"humidity"])  return s.humidity;
    if ([field isEqualToString:@"aqi"]) {
        if (!isnan(s.aqi) && s.aqi >= 0) return s.aqi;
        return ASAQIFromPM25(s.pm25);
    }
    return NAN;
}

NSArray<ASSample *> *ASSortSamples(NSArray<ASSample *> *samples)
{
    return [samples sortedArrayUsingComparator:^NSComparisonResult(ASSample *a, ASSample *b) {
        if (a.date == nil && b.date == nil) return NSOrderedSame;
        if (a.date == nil) return NSOrderedDescending;
        if (b.date == nil) return NSOrderedAscending;
        return [a.date compare:b.date];
    }];
}

#pragma mark - ASSeries

@interface ASSeries ()
@property (nonatomic, strong) NSMutableArray<ASSeriesPoint *> *acc;
@end

@implementation ASSeriesPoint
@end

@implementation ASSeries

- (instancetype)init
{
    if ((self = [super init])) {
        _points = @[];
        _acc = [NSMutableArray array];
        _latest = NAN;
        _delta = NAN;
        _label = @"";
        _unit = @"";
    }
    return self;
}

@end

#pragma mark - ASHistoryStore

@implementation ASHistoryStore {
    NSString *_path;
    NSMutableArray<ASSample *> *_samples;   // ascending
    dispatch_queue_t _q;
}

- (instancetype)initWithBasePath:(NSString *)basePath
{
    if ((self = [super init])) {
        _path = [basePath copy];
        _samples = [NSMutableArray array];
        _q = dispatch_queue_create("com.airsense.history", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)load:(NSError **)error
{
    __block NSString *data = nil;
    dispatch_sync(_q, ^{
        // A missing file is the normal first-run state, not an error.
        data = [NSString stringWithContentsOfFile:self->_path encoding:NSUTF8StringEncoding error:NULL];
    });
    if (data == nil) return YES;

    NSMutableArray<ASSample *> *parsed = [NSMutableArray array];
    for (NSString *line in [data componentsSeparatedByString:@"\n"]) {
        if (line.length == 0) continue;
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
        ASSample *s = ASParseLocalSample(obj);
        if (s == nil) continue;
        [parsed addObject:s];
    }

    dispatch_sync(_q, ^{
        [self->_samples removeAllObjects];
        [self->_samples addObjectsFromArray:ASSortSamples(parsed)];
    });
    return YES;
}

/// Missing fields are stored as JSON null so a NAN round-trips instead of becoming 0.
static id ASNumOrNull(double v) { return isnan(v) ? (id)[NSNull null] : @(v); }

static ASSample *ASParseLocalSample(id obj)
{
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *d = obj;
    NSNumber *t = ASDictNumber(d, @"t");
    if (t == nil) return nil;

    ASSample *s = [[ASSample alloc] init];
    s.date     = [NSDate dateWithTimeIntervalSince1970:t.doubleValue];
    s.pm25     = ASDictDouble(d, @"pm2_5");
    s.pm10     = ASDictDouble(d, @"pm10");
    s.co2      = ASDictDouble(d, @"co2");
    s.lpg      = ASDictDouble(d, @"lpg");
    s.co       = ASDictDouble(d, @"co");
    s.temp     = ASDictDouble(d, @"temp");
    s.humidity = ASDictDouble(d, @"humidity");
    s.aqi      = ASDictDouble(d, @"aqi");
    return s;
}

- (BOOL)save:(NSError **)error
{
    __block NSString *out = @"";
    dispatch_sync(_q, ^{
        NSMutableString *buf = [NSMutableString string];
        for (ASSample *s in self->_samples) {
            NSDictionary *d = @{
                @"t":    @([s.date timeIntervalSince1970]),
                @"pm2_5": ASNumOrNull(s.pm25),
                @"pm10":  ASNumOrNull(s.pm10),
                @"co2":   ASNumOrNull(s.co2),
                @"lpg":   ASNumOrNull(s.lpg),
                @"co":    ASNumOrNull(s.co),
                @"temp":  ASNumOrNull(s.temp),
                @"humidity": ASNumOrNull(s.humidity),
                @"aqi":   ASNumOrNull(s.aqi),
            };
            NSData *jd = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];
            if (jd == nil) continue;
            [buf appendString:[[NSString alloc] initWithData:jd encoding:NSUTF8StringEncoding]];
            [buf appendString:@"\n"];
        }
        out = buf;
    });

    NSError *writeErr = nil;
    BOOL wrote = [out writeToFile:_path atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
    if (!wrote && error) *error = writeErr;
    return wrote;
}

- (void)clear
{
    dispatch_sync(_q, ^{
        [self->_samples removeAllObjects];
    });
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
}

- (BOOL)appendSample:(ASSample *)s
{
    if (s == nil || s.date == nil) return NO;
    __block BOOL added = NO;
    dispatch_sync(_q, ^{
        ASSample *last = self->_samples.lastObject;
        if (last && [s.date timeIntervalSinceDate:last.date] < 5.0) return;   // dedupe poll jitter
        [self->_samples addObject:s];
        // ~60 days at one sample/minute is plenty for the 30-day tab.
        if (self->_samples.count > 90000) [self->_samples removeObjectsInRange:NSMakeRange(0, 1000)];
        added = YES;
    });
    return added;
}

- (NSArray<ASSample *> *)samplesInRange:(ASRange)range
{
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-ASRangeSeconds(range)];
    __block NSMutableArray<ASSample *> *out = [NSMutableArray array];
    dispatch_sync(_q, ^{
        for (ASSample *s in self->_samples) if ([s.date compare:cutoff] != NSOrderedAscending) [out addObject:s];
    });
    return out;
}

- (NSArray<NSString *> *)timestampsInRange:(ASRange)range
{
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-ASRangeSeconds(range)];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (ASSample *s in [self samplesInRange:range]) {
        if ([s.date compare:cutoff] == NSOrderedAscending) continue;
        [out addObject:ASISOFromDate(s.date) ?: @""];
    }
    return out;
}

- (NSUInteger)totalSampleCount
{
    __block NSUInteger n = 0;
    dispatch_sync(_q, ^{ n = self->_samples.count; });
    return n;
}

- (NSDate *)oldestSampleDate
{
    __block NSDate *d = nil;
    dispatch_sync(_q, ^{ d = self->_samples.firstObject.date; });
    return d;
}

#pragma mark - Series building

ASSeries *ASBuildSeries(NSArray<ASSample *> *samples, NSString *field,
                        NSString *label, NSString *unit, ASRange range, ASHistorySource source)
{
    ASSeries *series = [[ASSeries alloc] init];
    series.label = label ?: @"";
    series.unit = unit ?: @"";
    series.source = source;

    NSMutableArray<ASSeriesPoint *> *pts = [NSMutableArray array];
    for (ASSample *s in samples) {
        double v = ASSampleValue(s, field);
        if (isnan(v)) continue;
        ASSeriesPoint *p = [[ASSeriesPoint alloc] init];
        p.date = s.date;
        p.value = v;
        [pts addObject:p];
    }
    series.points = ASDownsample(pts, 240);
    if (series.points.count == 0) { series.source = ASHistorySourceNone; return series; }

    double sum = 0, lo = INFINITY, hi = -INFINITY;
    for (ASSeriesPoint *p in series.points) {
        sum += p.value;
        lo = MIN(lo, p.value);
        hi = MAX(hi, p.value);
    }
    series.avg = @(sum / (double)series.points.count);
    series.min = @(lo);
    series.max = @(hi);
    series.latest = series.points.lastObject.value;

    if (series.points.count >= 2) {
        double d = series.latest - series.points[series.points.count - 2].value;
        series.delta = d;
        series.trendRising  = d > 0;
        series.trendFalling = d < 0;
    }
    (void)range;
    return series;
}

ASSeries *ASBuildAQISeries(NSArray<ASSample *> *samples, ASRange range, ASHistorySource source)
{
    ASSeries *series = [[ASSeries alloc] init];
    series.label = @"AQI";
    series.unit = @"AQI";
    series.source = source;

    NSMutableArray<ASSeriesPoint *> *pts = [NSMutableArray array];
    for (ASSample *s in samples) {
        double v = (!isnan(s.aqi) && s.aqi >= 0) ? s.aqi : ASAQIFromPM25(s.pm25);
        if (isnan(v)) continue;
        ASSeriesPoint *p = [[ASSeriesPoint alloc] init];
        p.date = s.date;
        p.value = v;
        [pts addObject:p];
    }
    series.points = ASDownsample(pts, 240);
    if (series.points.count == 0) { series.source = ASHistorySourceNone; return series; }

    double sum = 0, lo = INFINITY, hi = -INFINITY;
    for (ASSeriesPoint *p in series.points) {
        sum += p.value;
        lo = MIN(lo, p.value);
        hi = MAX(hi, p.value);
    }
    series.avg = @(sum / (double)series.points.count);
    series.min = @(lo);
    series.max = @(hi);
    series.latest = series.points.lastObject.value;
    if (series.points.count >= 2) {
        double d = series.latest - series.points[series.points.count - 2].value;
        series.delta = d;
        series.trendRising  = d > 0;
        series.trendFalling = d < 0;
    }
    (void)range;
    return series;
}

NSArray<ASSeriesPoint *> *ASDownsample(NSArray<ASSeriesPoint *> *points, NSUInteger maxPoints)
{
    if (points.count <= maxPoints || maxPoints == 0) return points;
    double bucket = (double)points.count / (double)maxPoints;
    NSMutableArray<ASSeriesPoint *> *out = [NSMutableArray arrayWithCapacity:maxPoints];
    for (NSUInteger i = 0; i < maxPoints; i++) {
        NSUInteger lo = (NSUInteger)floor(i * bucket);
        NSUInteger hi = (NSUInteger)floor((i + 1) * bucket);
        if (hi > points.count) hi = points.count;
        if (lo >= hi) continue;
        double sum = 0;
        NSUInteger n = 0;
        for (NSUInteger k = lo; k < hi; k++) { sum += points[k].value; n++; }
        ASSeriesPoint *p = [[ASSeriesPoint alloc] init];
        p.date = points[(lo + hi) / 2].date;
        p.value = n ? sum / (double)n : 0;
        [out addObject:p];
    }
    return out;
}
@end
