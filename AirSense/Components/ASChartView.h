// ASChartView.h — Dependency-free line/area chart.
// Charts in the app all share this one implementation: gradient area fill, grid,
// axis labels and an optional AQI colour band behind the plot.

#import <UIKit/UIKit.h>
#import "Models/ASHistory.h"
#import "Design/ASDesign.h"

@interface ASChartView : UIView

@property (nonatomic, strong) ASSeries *series;
/// Draws the six EPA AQI category bands behind the plot.
@property (nonatomic, assign) BOOL showsAQIBands;
/// Highlights the last point with a dot and draws a focus crosshair.
@property (nonatomic, assign) BOOL showsFocusPoint;
/// Range being displayed, used for axis date formatting.
@property (nonatomic, assign) ASRange range;
/// Formats the x-axis label for a date; defaults to HH:mm.
@property (nonatomic, copy) NSString * (^axisFormatter)(NSDate *date, ASRange range);

- (void)setSeries:(ASSeries *)series animated:(BOOL)animated;

@end