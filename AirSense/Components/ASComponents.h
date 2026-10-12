// ASComponents.h — Reusable Liquid Glass views.
// Every screen is assembled from these; no view controller defines its own card styling.

#import <UIKit/UIKit.h>
#import "Design/ASDesign.h"
#import "Models/ASModels.h"

#pragma mark - GlassCard

/// Translucent, blurred, layered surface with a soft shadow and a hairline highlight.
@interface ASGlassCard : UIView
@property (nonatomic, strong, readonly) UIView *glassView;
@property (nonatomic, assign, readonly) BOOL emphasis;
@property (nonatomic, strong, readonly) CAGradientLayer *borderGradient;
@property (nonatomic, assign) CGFloat contentInset;

/// Standard configuration. `emphasis` thickens the border for the primary card on a screen.
- (instancetype)initWithEmphasis:(BOOL)emphasis;
@end

#pragma mark - StatusBadge

@interface ASStatusBadge : UIView
- (instancetype)initWithText:(NSString *)text color:(UIColor *)color;
- (void)applyText:(NSString *)text color:(UIColor *)color;
@property (nonatomic, strong, readonly) UILabel *label;
@end

#pragma mark - AQIRing

/// The dashboard's hero element: a gradient progress ring whose sweep is the AQI
/// position on the 0-500 scale, with the value and category in the middle.
@interface ASAQIRing : UIView
@property (nonatomic, assign) double value;          // NAN => unavailable
@property (nonatomic, assign) ASAQILevel level;
/// Animates from the previous value; no-op on first layout.
- (void)setValue:(double)value level:(ASAQILevel)level animated:(BOOL)animated;
- (void)layoutSubviews;
@end

#pragma mark - MetricCard

/// One sensor reading: name, value + unit, status pill and a threshold bar.
@interface ASMetricCard : UIView
- (instancetype)initWithReading:(ASReading *)reading;
- (void)applyReading:(ASReading *)reading;
@property (nonatomic, strong, readonly) NSString *metricKey;
@property (nonatomic, strong, readonly) ASStatusBadge *badge;
@end

#pragma mark - KeyValueRow

/// Label/value pair used in every detail list.
@interface ASKeyValueRow : UIView
- (instancetype)initWithLabel:(NSString *)label value:(NSString *)value;
- (void)applyLabel:(NSString *)label value:(NSString *)value valueColor:(UIColor * _Nullable)color;
- (void)setSymbolName:(NSString * _Nullable)symbol;
@property (nonatomic, readonly) UIStackView *stack;
@end

#pragma mark - State views

@interface ASLoadingView : UIView
- (instancetype)initWithMessage:(NSString *)message;
@end

/// Shimmering placeholder block. `skeletonHeight` and corner are configurable.
@interface ASSkeletonBlock : UIView
@property (nonatomic, assign) CGFloat skeletonHeight;
@property (nonatomic, assign) CGFloat skeletonRadius;
- (void)startShimmering;
- (void)stopShimmering;
@end

@interface ASEmptyStateView : UIView
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title message:(NSString *)message;
- (void)applyTitle:(NSString *)title message:(NSString *)message;
@property (nonatomic, copy) void (^actionHandler)(void);
- (void)setActionTitle:(NSString * _Nullable)title;
@end

@interface ASErrorStateView : UIView
- (instancetype)initWithMessage:(NSString *)message retryTitle:(NSString * _Nullable)retryTitle;
- (void)applyMessage:(NSString *)message retryTitle:(NSString * _Nullable)retryTitle;
@property (nonatomic, copy) void (^retryHandler)(void);
@end

/// Thin banner shown above content while offline or showing cached data.
@interface ASStatusBanner : UIView
- (void)applyText:(NSString *)text symbol:(NSString *)symbol color:(UIColor *)color;
- (void)hide;
@end

#pragma mark - Buttons

@interface ASGlassButton : UIButton
+ (instancetype)primaryButtonWithTitle:(NSString *)title symbol:(NSString * _Nullable)symbol;
+ (instancetype)secondaryButtonWithTitle:(NSString *)title symbol:(NSString * _Nullable)symbol;
/// Destructive/alert style, used for the buzzer.
+ (instancetype)dangerButtonWithTitle:(NSString *)title symbol:(NSString * _Nullable)symbol;
- (void)setLoading:(BOOL)loading;
@end

#pragma mark - Segmented control

/// Glassy replacement for UISegmentedControl, tuned for the Liquid Glass look.
@interface ASSegmentedControl : UIControl
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) NSArray<NSString *> *titles;
- (void)setTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)index;
/// Updates the highlight without emitting UIControlEventValueChanged.
/// Pass -1 to show no selection at all — used when the device does not report a mode.
- (void)setSelectedIndexSilently:(NSInteger)index;
@end
