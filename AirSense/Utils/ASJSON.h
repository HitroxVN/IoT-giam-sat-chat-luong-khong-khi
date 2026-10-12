#pragma clang diagnostic ignored "-Wnullability-completeness"

// ASJSON.h — Safe typed accessors for the loosely-typed ESP32 / Firebase payloads.
// Every accessor tolerates a wrong type and returns the fallback instead of throwing,
// because a malformed frame must never crash the app.

#import <Foundation/Foundation.h>

NSNumber   * ASDictNumber (NSDictionary * _Nullable d, NSString *key);
NSString   * ASDictString (NSDictionary * _Nullable d, NSString *key);
BOOL         ASDictBool   (NSDictionary * _Nullable d, NSString *key, BOOL fallback);
NSDictionary* ASDictDict   (NSDictionary * _Nullable d, NSString *key);
NSArray     * ASDictArray  (NSDictionary * _Nullable d, NSString *key);

/// Reads key -> subkey in one hop: ASDictDeepNum(dict, @"env", @"temp_c")
NSNumber   * ASDictDeepNumber (NSDictionary * _Nullable d, NSString *outer, NSString *inner);

/// Trimmed float, or NAN when absent/unparsable.
double       ASDictDouble (NSDictionary * _Nullable d, NSString *key);

/// @"3.4" from @(3.4), @"6" from @(6). Never scientific notation.
NSString   * ASPlainNumber (double v);

/// Shortest representation that still has a decimal part: 12, 12.4, 12.45
NSString   * ASTrimNumber (double v);

double       ASClampDouble (double v, double lo, double hi);

/// ISO-8601 with fractional seconds, falling back to plain ISO-8601.
/// Returns nil when the value is not a string at all.
NSDate    * ASDateFromISO (NSString * _Nullable s);
NSString  * ASISOFromDate (NSDate *date);