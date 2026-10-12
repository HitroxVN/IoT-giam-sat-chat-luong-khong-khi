#pragma clang diagnostic ignored "-Wnullability-completeness"

// ASHistory.h — Pure series/chart logic. No UIKit.
// The ESP exposes no history endpoint, so samples come from the Firebase Realtime Database
// REST tree `esp32/history` (which the firmware pushes) and from `esp32/latest`.
// Every series carries an explicit provenance flag so the UI can distinguish
// "read from Firebase" from "recorded on this phone" from "nothing yet".

#import <Foundation/Foundation.h>

/// User-facing strings live in ASModels; ASLevelName is the shared typedef for them.
typedef NSString *ASLevelName;

typedef NS_ENUM(NSInteger, ASHistorySource) {
    ASHistorySourceNone = 0,
    ASHistorySourceFirebase,
    ASHistorySourceDevice,     // local samples recorded while the app polled /api/data
};

typedef NS_ENUM(NSInteger, ASRange) {
    ASRange1H  = 0,
    ASRange6H,
    ASRange24H,
    ASRange7D,
    ASRange30D,
};

ASLevelName ASRangeName(ASRange r);
/// Seconds covered by the range.
NSTimeInterval ASRangeSeconds(ASRange r);
/// Single tick spacing to request from Firebase REST when reading that range.
NSTimeInterval ASRangeFirebaseFetchSeconds(ASRange r);

@interface ASSample : NSObject
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) double  pm25;      // NAN when absent
@property (nonatomic, assign) double  pm10;
@property (nonatomic, assign) double  co2;
@property (nonatomic, assign) double  lpg;
@property (nonatomic, assign) double  co;
@property (nonatomic, assign) double  temp;
@property (nonatomic, assign) double  humidity;
@property (nonatomic, assign) double  aqi;       // NAN when absent
@end

@interface ASSeriesPoint : NSObject
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) double  value;
@end

@interface ASSeries : NSObject
@property (nonatomic, copy)   NSArray<ASSeriesPoint *> *points;
@property (nonatomic, copy)   NSString *unit;
@property (nonatomic, copy)   NSString *label;
@property (nonatomic, strong) NSNumber *avg;
@property (nonatomic, strong) NSNumber *min;
@property (nonatomic, strong) NSNumber *max;
@property (nonatomic, assign) double  latest;
/// Change from the previous point; NAN when fewer than two points.
@property (nonatomic, assign) double  delta;
@property (nonatomic, assign) BOOL    trendRising;
@property (nonatomic, assign) BOOL    trendFalling;
@property (nonatomic, assign) ASHistorySource source;
@end

@interface ASHistoryStore : NSObject
- (instancetype)initWithBasePath:(NSString *)basePath;
- (BOOL)load:(NSError **)error;
- (BOOL)save:(NSError **)error;
- (void)clear;

/// Appends a sample. Duplicate timestamps within 5s are ignored so the poll timer
/// cannot inflate the log.
- (BOOL)appendSample:(ASSample *)s;

- (NSArray<ASSample *> *)samplesInRange:(ASRange)range;
/// ISO-8601 timestamps of samples inside the range — drives the "coverage" notice.
- (NSArray<NSString *> *)timestampsInRange:(ASRange)range;
- (NSUInteger)totalSampleCount;
- (NSDate *)oldestSampleDate;
@end

#pragma mark - Parsing Firebase payloads

/// Firebase keys each pushed node with a push id ("-Nabc123") that carries no timestamp,
/// so we pass the request time and treat key order as time order.
ASSample  * ASParseSample(NSDictionary * _Nullable json);
NSArray<NSString *> * ASExtractFirebaseKeys(NSDictionary * _Nullable json);

/// Turns a `esp32/history` node into chronological samples.
/// Push IDs are monotonically increasing, so key order is time order. The newest node is
/// stamped `now` and earlier nodes step backwards by `intervalSeconds` (the ESP's
/// firebase.interval_ms, default 30). Older entries are dropped by `cutoff`.
NSArray<ASSample *> * ASParseFirebaseHistory(NSDictionary * _Nullable json,
                                             NSTimeInterval intervalSeconds,
                                             NSDate *now,
                                             NSDate * _Nullable cutoff);

/// Extracts a value from a sample node for a given field. NAN when the path is absent,
/// which is how a partial `latest` payload yields a sparse series.
double ASSampleValue(ASSample *s, NSString *field);

/// Drops samples with no timestamp and sorts ascending. Shared by every source.
NSArray<ASSample *> * ASSortSamples(NSArray<ASSample *> *samples);

/// Series for one field over a time range. `source` describes where the samples came from.
ASSeries * ASBuildSeries(NSArray<ASSample *> *samples, NSString *field,
                         NSString *label, NSString *unit, ASRange range, ASHistorySource source);

/// Down-samples to at most `maxPoints` by averaging buckets, so charts stay smooth
/// on a 30-day range without drawing 2,880 points.
NSArray<ASSeriesPoint *> * ASDownsample(NSArray<ASSeriesPoint *> *points, NSUInteger maxPoints);

/// Overall AQI series derived from the PM2.5 series — same formula as the live card.
ASSeries * ASBuildAQISeries(NSArray<ASSample *> *samples, ASRange range, ASHistorySource source);