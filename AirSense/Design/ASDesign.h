// ASDesign.h — Liquid Glass design tokens.
// One source of truth for colour, type, spacing and motion so every card on every
// screen shares the same visual language. All colours are dynamic: they resolve
// against the current UITraitCollection, so Light/Dark needs no branching.

#import <UIKit/UIKit.h>
#import "Models/ASModels.h"

#pragma mark - Palette

@interface ASDesign : NSObject

/// Tiered background gradient behind everything, tinted by the current AQI level.
+ (CAGradientLayer *)ambientBackgroundForLevel:(ASAQILevel)level;
+ (UIColor *)ambientTopForLevel:(ASAQILevel)level;
+ (UIColor *)ambientBottomForLevel:(ASAQILevel)level;

/// Glass surface layers.
+ (UIColor *)glassFill;
+ (UIColor *)glassFillStrong;
+ (UIColor *)glassStroke;
+ (UIColor *)glassHighlight;
+ (UIColor *)separator;

/// Text.
+ (UIColor *)primaryText;
+ (UIColor *)secondaryText;
+ (UIColor *)tertiaryText;

/// Semantic status colours, keyed to AQI category.
+ (UIColor *)colorForLevel:(ASAQILevel)level;
+ (UIColor *)colorForLevelDim:(ASAQILevel)level;
+ (UIColor *)goodColor;
+ (UIColor *)warningColor;
+ (UIColor *)dangerColor;

/// Used for solid-accent buttons. Brighter green in light mode so the CTA pops
/// against the dark glass surface; softer tint in dark mode to avoid flare.
+ (UIColor *)primaryActionTint;

#pragma mark - Metrics

+ (CGFloat)cardRadius;
+ (CGFloat)cardInset;         // horizontal page margin
+ (CGFloat)cardPadding;
+ (CGFloat)stackSpacing;

#pragma mark - Type scale

+ (UIFont *)displayFont;      // AQI number
+ (UIFont *)metricFont;       // card value
+ (UIFont *)titleFont;
+ (UIFont *)headlineFont;
+ (UIFont *)bodyFont;
+ (UIFont *)captionFont;
+ (UIFont *)microFont;        // status pills, axis labels

#pragma mark - Motion

+ (CGFloat)quickDuration;     // 0.22
+ (CGFloat)mediumDuration;    // 0.38
+ (CGFloat)springDamping;
+ (void)hapticLight;
+ (void)hapticSuccess;
+ (void)hapticWarning;
+ (void)hapticError;

@end

#pragma mark - Shared builder helpers

/// Number of grid columns that fits `width` at the given minimum cell width.
/// Used by every card grid so iPhone SE and Pro Max both lay out correctly.
NSInteger ASGridColumnCount(CGFloat availableWidth, CGFloat minCellWidth, CGFloat spacing);

/// Convenience: a UIFont with rounded design, falling back to the system face.
UIFont * ASFont(CGFloat size, UIFontWeight weight);