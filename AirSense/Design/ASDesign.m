#import "Design/ASDesign.h"

static UIColor *ASDynamicHex(uint32_t light, uint32_t dark)
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:((dark >> 16) & 0xFF) / 255.0
                               green:((dark >> 8) & 0xFF) / 255.0
                                blue:(dark & 0xFF) / 255.0
                               alpha:1]
            : [UIColor colorWithRed:((light >> 16) & 0xFF) / 255.0
                               green:((light >> 8) & 0xFF) / 255.0
                                blue:(light & 0xFF) / 255.0
                               alpha:1];
    }];
}

static UIColor *ASDynamicRGB(uint32_t rgb, double alpha, uint32_t rgbDark, double alphaDark)
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        BOOL dark = tc.userInterfaceStyle == UIUserInterfaceStyleDark;
        uint32_t c = dark ? rgbDark : rgb;
        return [UIColor colorWithRed:((c >> 16) & 0xFF) / 255.0
                               green:((c >> 8) & 0xFF) / 255.0
                                blue:(c & 0xFF) / 255.0
                               alpha:dark ? alphaDark : alpha];
    }];
}

UIFont *ASFont(CGFloat size, UIFontWeight weight)
{
    UIFont *f = nil;
    f = [UIFont systemFontOfSize:size weight:weight];
    if (@available(iOS 13.0, *)) {
        UIFontDescriptor *d = [UIFontDescriptor fontDescriptorWithFontAttributes:
                               @{UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(weight)}}];
        UIFontDescriptor *rounded = [d fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        f = rounded ? [UIFont fontWithDescriptor:rounded size:size] : f;
    }
    return f;
}

NSInteger ASGridColumnCount(CGFloat availableWidth, CGFloat minCellWidth, CGFloat spacing)
{
    if (minCellWidth <= 0) return 1;
    NSInteger cols = (NSInteger)floor((availableWidth + spacing) / (minCellWidth + spacing));
    if (cols < 1) return 1;
    if (cols > 4) return 4;
    return cols;
}

@implementation ASDesign

#pragma mark - Ambient background

+ (UIColor *)ambientTopForLevel:(ASAQILevel)level
{
    switch (level) {
        case ASAQILevelGood:         return ASDynamicHex(0xEAF4FF, 0x0B1220);
        case ASAQILevelModerate:     return ASDynamicHex(0xFDF6E3, 0x14120B);
        case ASAQILevelSensitive:    return ASDynamicHex(0xFFF0E2, 0x17100A);
        case ASAQILevelUnhealthy:    return ASDynamicHex(0xFFE8E6, 0x180C0C);
        case ASAQILevelVeryUnhealthy:return ASDynamicHex(0xFDE4E8, 0x190A10);
        case ASAQILevelHazardous:    return ASDynamicHex(0xF8DFE4, 0x1B0A12);
        case ASAQILevelUnknown:      break;
    }
    return ASDynamicHex(0xF1F2F7, 0x0D0F16);
}

+ (UIColor *)ambientBottomForLevel:(ASAQILevel)level
{
    switch (level) {
        case ASAQILevelGood:         return ASDynamicHex(0xF6FAFF, 0x080A11);
        case ASAQILevelModerate:     return ASDynamicHex(0xFFFCF4, 0x0C0B07);
        case ASAQILevelSensitive:    return ASDynamicHex(0xFFF8F1, 0x0E0A06);
        case ASAQILevelUnhealthy:    return ASDynamicHex(0xFFF4F3, 0x0C0707);
        case ASAQILevelVeryUnhealthy:return ASDynamicHex(0xFFF2F5, 0x0D060A);
        case ASAQILevelHazardous:    return ASDynamicHex(0xFCF0F3, 0x0E050A);
        case ASAQILevelUnknown:      break;
    }
    return ASDynamicHex(0xFAFAFC, 0x07080C);
}

+ (CAGradientLayer *)ambientBackgroundForLevel:(ASAQILevel)level
{
    CAGradientLayer *g = [CAGradientLayer layer];
    g.startPoint = CGPointMake(0.5, 0.0);
    g.endPoint = CGPointMake(0.5, 1.0);
    g.colors = @[(id)[self ambientTopForLevel:level].CGColor,
                 (id)[self ambientBottomForLevel:level].CGColor];
    return g;
}

#pragma mark - Glass

+ (UIColor *)glassFill        { return ASDynamicRGB(0xFFFFFF, 0.58, 0xFFFFFF, 0.10); }
+ (UIColor *)glassFillStrong  { return ASDynamicRGB(0xFFFFFF, 0.80, 0xFFFFFF, 0.16); }
+ (UIColor *)glassStroke      { return ASDynamicRGB(0xFFFFFF, 0.70, 0xFFFFFF, 0.18); }
+ (UIColor *)glassHighlight   { return ASDynamicRGB(0xFFFFFF, 0.90, 0xFFFFFF, 0.28); }
+ (UIColor *)separator        { return ASDynamicRGB(0x8A8A8E, 0.18, 0xFFFFFF, 0.14); }

#pragma mark - Text

+ (UIColor *)primaryText
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor whiteColor] : [UIColor colorWithWhite:0.07 alpha:1];
    }];
}

+ (UIColor *)secondaryText
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1 alpha:0.66]
            : [UIColor colorWithWhite:0.32 alpha:1];
    }];
}

+ (UIColor *)tertiaryText
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1 alpha:0.42]
            : [UIColor colorWithWhite:0.52 alpha:1];
    }];
}

#pragma mark - Semantic colours

+ (UIColor *)goodColor     { return ASDynamicHex(0x1FA971, 0x34D399); }
+ (UIColor *)warningColor  { return ASDynamicHex(0xD97706, 0xFBBF24); }
+ (UIColor *)dangerColor   { return ASDynamicHex(0xDC2626, 0xF87171); }

+ (UIColor *)primaryActionTint
{
    return ASDynamicHex(0x22C55E, 0x4ADE80);
}

+ (UIColor *)colorForLevel:(ASAQILevel)level
{
    switch (level) {
        case ASAQILevelGood:          return [self goodColor];
        case ASAQILevelModerate:      return ASDynamicHex(0xB45309, 0xFBBF24);
        case ASAQILevelSensitive:     return ASDynamicHex(0xC2410C, 0xFB923C);
        case ASAQILevelUnhealthy:     return ASDynamicHex(0xDC2626, 0xF87171);
        case ASAQILevelVeryUnhealthy: return ASDynamicHex(0xB91C1C, 0xF87171);
        case ASAQILevelHazardous:     return ASDynamicHex(0x7F1D1D, 0xEF4444);
        case ASAQILevelUnknown:       break;
    }
    return [self secondaryText];
}

+ (UIColor *)colorForLevelDim:(ASAQILevel)level
{
    return [[self colorForLevel:level] colorWithAlphaComponent:0.16];
}

#pragma mark - Metrics

+ (CGFloat)cardRadius   { return 26.0; }
+ (CGFloat)cardInset    { return 18.0; }
+ (CGFloat)cardPadding  { return 16.0; }
+ (CGFloat)stackSpacing { return 14.0; }

#pragma mark - Type scale

+ (UIFont *)displayFont  { return ASFont(60, UIFontWeightBold); }
+ (UIFont *)metricFont  { return ASFont(27, UIFontWeightSemibold); }
+ (UIFont *)titleFont   { return ASFont(22, UIFontWeightBold); }
+ (UIFont *)headlineFont{ return ASFont(17, UIFontWeightSemibold); }
+ (UIFont *)bodyFont    { return ASFont(15, UIFontWeightRegular); }
+ (UIFont *)captionFont { return ASFont(13, UIFontWeightMedium); }
+ (UIFont *)microFont   { return ASFont(11, UIFontWeightSemibold); }

#pragma mark - Motion

+ (CGFloat)quickDuration    { return 0.22; }
+ (CGFloat)mediumDuration   { return 0.38; }
+ (CGFloat)springDamping    { return 0.78; }

+ (void)hapticLight
{
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g prepare]; [g impactOccurred];
}

+ (void)hapticSuccess
{
    UINotificationFeedbackGenerator *g = [[UINotificationFeedbackGenerator alloc] init];
    [g prepare]; [g notificationOccurred:UINotificationFeedbackTypeSuccess];
}

+ (void)hapticWarning
{
    UINotificationFeedbackGenerator *g = [[UINotificationFeedbackGenerator alloc] init];
    [g prepare]; [g notificationOccurred:UINotificationFeedbackTypeWarning];
}

+ (void)hapticError
{
    UINotificationFeedbackGenerator *g = [[UINotificationFeedbackGenerator alloc] init];
    [g prepare]; [g notificationOccurred:UINotificationFeedbackTypeError];
}

@end
