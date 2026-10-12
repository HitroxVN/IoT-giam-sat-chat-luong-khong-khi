#import "Utils/ASJSON.h"

static NSNumber *ASNumberValue(id v)
{
    if ([v isKindOfClass:[NSNumber class]]) return v;
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (s.length == 0) return nil;
        NSScanner *sc = [NSScanner scannerWithString:s];
        double d = 0;
        if (![sc scanDouble:&d] || !sc.isAtEnd) return nil;
        return @(d);
    }
    return nil;
}

NSNumber *ASDictNumber(NSDictionary *d, NSString *key)
{
    if (![d isKindOfClass:[NSDictionary class]] || key == nil) return nil;
    return ASNumberValue(d[key]);
}

NSString *ASDictString(NSDictionary *d, NSString *key)
{
    if (![d isKindOfClass:[NSDictionary class]] || key == nil) return nil;
    id v = d[key];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length ? s : nil;
    }
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return nil;
}

BOOL ASDictBool(NSDictionary *d, NSString *key, BOOL fallback)
{
    if (![d isKindOfClass:[NSDictionary class]] || key == nil) return fallback;
    id v = d[key];
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v boolValue];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v lowercaseString];
        if ([s isEqualToString:@"true"] || [s isEqualToString:@"1"] || [s isEqualToString:@"yes"]) return YES;
        if ([s isEqualToString:@"false"] || [s isEqualToString:@"0"] || [s isEqualToString:@"no"]) return NO;
    }
    return fallback;
}

NSDictionary *ASDictDict(NSDictionary *d, NSString *key)
{
    if (![d isKindOfClass:[NSDictionary class]] || key == nil) return nil;
    id v = d[key];
    return [v isKindOfClass:[NSDictionary class]] ? v : nil;
}

NSArray *ASDictArray(NSDictionary *d, NSString *key)
{
    if (![d isKindOfClass:[NSDictionary class]] || key == nil) return nil;
    id v = d[key];
    return [v isKindOfClass:[NSArray class]] ? v : nil;
}

NSNumber *ASDictDeepNumber(NSDictionary *d, NSString *outer, NSString *inner)
{
    return ASDictNumber(ASDictDict(d, outer), inner);
}

double ASDictDouble(NSDictionary *d, NSString *key)
{
    NSNumber *n = ASDictNumber(d, key);
    return n ? n.doubleValue : NAN;
}

NSString *ASPlainNumber(double v)
{
    if (isnan(v) || isinf(v)) return @"--";
    return [NSString stringWithFormat:@"%.2f", v];
}

NSString *ASTrimNumber(double v)
{
    if (isnan(v) || isinf(v)) return @"--";
    NSString *two = [NSString stringWithFormat:@"%.2f", v];
    NSString *one  = [NSString stringWithFormat:@"%.1f", v];
    NSString *zero = [NSString stringWithFormat:@"%.0f", v];
    // Prefer the shortest form that survives a round-trip, so we never print 12.00 or 12.0.
    if (two.doubleValue == [one doubleValue]) {
        if (one.doubleValue == [zero doubleValue]) return zero;
        return one;
    }
    return two;
}

double ASClampDouble(double v, double lo, double hi)
{
    if (isnan(v)) return lo;
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

NSDate *ASDateFromISO(NSString *s)
{
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return nil;
    static NSISO8601DateFormatter *frac;
    static NSISO8601DateFormatter *plain;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        frac = [[NSISO8601DateFormatter alloc] init];
        frac.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        plain = [[NSISO8601DateFormatter alloc] init];
        plain.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [frac dateFromString:s] ?: [plain dateFromString:s];
}

NSString *ASISOFromDate(NSDate *date)
{
    static NSISO8601DateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSISO8601DateFormatter alloc] init];
        fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    return [fmt stringFromDate:date];
}