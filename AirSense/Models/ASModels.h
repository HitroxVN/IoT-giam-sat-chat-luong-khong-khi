#pragma clang diagnostic ignored "-Wnullability-completeness"

// ASModels.h — Domain models + pure analysis (no UIKit, no networking).
// This layer is compiled and unit-tested on the host in Step 4b.

#import <Foundation/Foundation.h>

/// Convenience alias — analysis output is user-facing text.
typedef NSString *ASLevelName;

#pragma mark - AQI categories

typedef NS_ENUM(NSInteger, ASAQILevel) {
    ASAQILevelUnknown = 0,
    ASAQILevelGood,
    ASAQILevelModerate,
    ASAQILevelSensitive,   // US EPA renamed "Unhealthy for Sensitive Groups"
    ASAQILevelUnhealthy,
    ASAQILevelVeryUnhealthy,
    ASAQILevelHazardous,
};

/// EPA 2024 PM2.5 breakpoints. Concentration is the 24h-truncated value in ug/m3.
extern const double kASAQIPM25CleanCutoff;   // 9.0  — above this the sub-index is on a 0-500 scale
extern const double kASAQIPM25TopCutoff;      // 325.4 — above this the sub-index cannot be derived

/// Convenience alias — analysis output is user-facing text.
ASLevelName ASAQILevelName(ASAQILevel lvl);
ASLevelName ASAQILevelDescription(ASAQILevel lvl);
/// Short status pill for metric cards, e.g. "Normal" / "Cảnh báo" / "Nặng".
ASLevelName ASAQILevelShortLabel(ASAQILevel lvl);

/// US EPA AQI sub-index derived from PM2.5.
/// Returns NAN when pm25 is missing, negative, or above the formula's 325.4 ug/m3 ceiling
/// (beyond which PM2.5 alone cannot express the index). Callers must show "--", never a guess.
double ASAQIFromPM25(double pm25);

/// EPA-style AQI category -> PM2.5 breakpoints (ug/m3), used to invert AQI back into a
/// concentration band. Returns NO when aqi is out of the 0-500 range.
BOOL ASAQIPM25RangeForAQI(double aqi, double *outLow, double *outHigh);

/// Maps a raw concentration to its level using the ESP's own alert thresholds.
ASAQILevel ASAQILevelForMetric(double value, double threshold);

/// EPA AQI -> category.
ASAQILevel ASAQILevelForValue(double aqi);

#pragma mark - Sensor reading

typedef NS_ENUM(NSInteger, ASSensorKind) {
    ASSensorKindPM25 = 0,
    ASSensorKindPM10,
    ASSensorKindCO2,
    ASSensorKindLPG,
    ASSensorKindCO,
    ASSensorKindTemp,
    ASSensorKindHumidity,
};

@interface ASReading : NSObject
@property (nonatomic, copy)   NSString *key;        // threshold API key: "pm2_5", "pm10", "co2", "lpg", "co"
@property (nonatomic, copy)   NSString *label;      // "PM2.5"
@property (nonatomic, copy)   NSString *symbol;     // SF Symbol
@property (nonatomic, copy)   NSString *unit;       // "µg/m³", "ppm", "°C", "%"
@property (nonatomic, strong) NSNumber *value;      // nil when absent
@property (nonatomic, assign) double threshold;     // NAN when the metric cannot alert
@property (nonatomic, assign) ASSensorKind kind;
@property (nonatomic, copy)   NSString *note;       // secondary line: "Tham chiếu", "ADC 3150", ...

@property (nonatomic, readonly) BOOL   hasValue;
@property (nonatomic, readonly) BOOL   alerts;      // value >= threshold and the metric can alert
@property (nonatomic, readonly) ASAQILevel level;
@property (nonatomic, readonly) double ratio;       // value/threshold, 0 when not alerting
@end

#pragma mark - MQ gas sensor

@interface ASGasSensor : NSObject
@property (nonatomic, copy)   NSString *key;    // mq135 / mq2 / mq7
@property (nonatomic, copy)   NSString *gas;    // CO2 / LPG / CO
@property (nonatomic, strong) NSNumber *ppm;
@property (nonatomic, strong) NSNumber *adc;
@property (nonatomic, strong) NSNumber *r0;
@property (nonatomic, strong) NSNumber *a;
@property (nonatomic, strong) NSNumber *b;
@property (nonatomic, assign) BOOL valid;

@property (nonatomic, readonly) BOOL   negative;    // ppm < 0 => failed read
@property (nonatomic, readonly) double adcFraction; // adc/4095 clamped to 0..1
@end

#pragma mark - MQ payload wrapper

@interface ASGasReading : NSObject
@property (nonatomic, copy) NSArray<ASGasSensor *> *sensors;
- (ASGasSensor * _Nullable)sensorForKey:(NSString *)key;
@end

#pragma mark - Alert state (derived purely from /api/data)

@interface ASAlert : NSObject
@property (nonatomic, assign) BOOL     danger;
@property (nonatomic, copy)   NSString *level;    // "safe", "warning", "danger"
@property (nonatomic, assign) NSInteger led;      // actual pin state, 0/1
@property (nonatomic, assign) NSInteger buzzer;   // actual pin state, 0/1
@property (nonatomic, assign) NSInteger fan;      // actual pin state, 0/1 (D18)
/// One entry per metric currently at or above its threshold. Empty when danger == NO.
@property (nonatomic, copy)   NSArray<ASReading *> *tripped;
@end

#pragma mark - Firebase sync state

@interface ASFirebaseState : NSObject
@property (nonatomic, assign) BOOL     enabled;
@property (nonatomic, strong) NSNumber *lastCode;   // 0 = never sent
@property (nonatomic, strong) NSNumber *intervalMs;
@end

#pragma mark - Thresholds

@interface ASThresholds : NSObject
@property (nonatomic, assign) double co2;
@property (nonatomic, assign) double lpg;
@property (nonatomic, assign) double co;
@property (nonatomic, assign) double pm25;
@property (nonatomic, assign) double pm10;
/// YES when any key is missing so Settings can flag "defaults, not read from device".
@property (nonatomic, assign) BOOL partial;
@end

/// Maps AQI category string from API or EPA/VN standard to ASAQILevel.
ASAQILevel ASAQILevelForCategory(NSString * _Nullable category);

#pragma mark - Full device snapshot — one GET /api/data

@interface ASSnapshot : NSObject
@property (nonatomic, copy)   NSString *device;
@property (nonatomic, strong) NSNumber *uptimeMs;
@property (nonatomic, assign) BOOL     wifiConnected;
@property (nonatomic, copy)   NSString *ssid;
@property (nonatomic, strong) NSNumber *rssi;
@property (nonatomic, assign) BOOL     envValid;
@property (nonatomic, assign) BOOL     dustValid;
@property (nonatomic, strong) NSNumber *aqiValue;       // From API "aqi": { "value": 148 }
@property (nonatomic, copy)   NSString *aqiCategory;    // From API "aqi": { "category": "Kém" }
@property (nonatomic, strong) ASThresholds  *thresholds;
@property (nonatomic, strong) ASAlert      *alert;
@property (nonatomic, strong) ASFirebaseState *firebase;
@property (nonatomic, copy)   NSArray<ASReading *> *readings;   // in dashboard order
@property (nonatomic, strong) NSDate *receivedAt;               // when the app got it

@property (nonatomic, readonly) ASReading *pm25;
@property (nonatomic, readonly) ASReading *co2;
@property (nonatomic, readonly) double  aqi;        // API aqi.value, falls back to PM2.5 formula
@property (nonatomic, readonly) ASAQILevel aqiLevel;
/// Worst metric right now, nil when nothing exceeds its threshold.
@property (nonatomic, readonly) ASReading *worst;
@end

#pragma mark - Parsing

/// Never raises: a malformed payload yields a snapshot with empty readings.
ASSnapshot * ASParseSnapshot(NSDictionary * _Nullable json);
ASGasReading * ASParseGasReading(NSDictionary * _Nullable json);
ASGasSensor * ASParseGasSensor(NSDictionary * _Nullable json);
ASThresholds * ASParseThresholds(NSDictionary * _Nullable json);

/// Human-readable server error from {"error":"..."} plus the status code.
NSString * ASExtractError(NSDictionary * _Nullable json, NSInteger statusCode);

#pragma mark - Derived analysis

/// AQI band expanded into plain-language advice. Driven by the measured AQI, never fixed text.
ASLevelName ASAQIAdviceHeadline(double aqi, ASAQILevel lvl);
ASLevelName ASAQIAdviceBody(double aqi, ASAQILevel lvl);
/// 0..1 share of the AQI scale (0-500) that is currently consumed.
double ASAQISeverityFraction(double aqi);