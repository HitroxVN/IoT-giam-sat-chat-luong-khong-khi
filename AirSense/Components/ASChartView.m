#import "Components/ASChartView.h"
#import "Models/ASModels.h"
#import "Utils/ASJSON.h"
#import "Services/ASAPIClient.h"

@implementation ASChartView {
    NSArray<ASSeriesPoint *> *_points;
    CGFloat _minValue;
    CGFloat _maxValue;
    UIColor *_accent;
    CAShapeLayer *_lineLayer;
    CAGradientLayer *_fillGradientLayer;
    CAShapeLayer *_fillMaskLayer;
    CAShapeLayer *_gridLayer;
    CAShapeLayer *_bandLayer;
    CALayer *_focusDot;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        _accent = [ASDesign goodColor];

        _bandLayer = [CAShapeLayer layer];
        _bandLayer.fillColor = [UIColor clearColor].CGColor;
        [self.layer addSublayer:_bandLayer];

        _gridLayer = [CAShapeLayer layer];
        _gridLayer.fillColor = [UIColor clearColor].CGColor;
        _gridLayer.strokeColor = [ASDesign separator].CGColor;
        _gridLayer.lineWidth = 1;
        [self.layer addSublayer:_gridLayer];

        _fillGradientLayer = [CAGradientLayer layer];
        _fillGradientLayer.startPoint = CGPointMake(0, 0);
        _fillGradientLayer.endPoint = CGPointMake(0, 1);
        _fillMaskLayer = [CAShapeLayer layer];
        _fillMaskLayer.fillColor = [UIColor blackColor].CGColor;
        _fillGradientLayer.mask = _fillMaskLayer;
        [self.layer addSublayer:_fillGradientLayer];

        _lineLayer = [CAShapeLayer layer];
        _lineLayer.fillColor = [UIColor clearColor].CGColor;
        _lineLayer.lineWidth = 2.4;
        _lineLayer.lineJoin = kCALineJoinRound;
        _lineLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_lineLayer];

        _focusDot = [CALayer layer];
        _focusDot.opacity = 0;
        [self.layer addSublayer:_focusDot];
    }
    return self;
}

- (void)setSeries:(ASSeries *)series animated:(BOOL)animated
{
    _series = series;
    _points = series.points;
    if (series.points.count == 0) {
        _minValue = 0; _maxValue = 1;
    } else {
        CGFloat lo = INFINITY, hi = -INFINITY;
        for (ASSeriesPoint *p in series.points) {
            lo = MIN(lo, (CGFloat)p.value);
            hi = MAX(hi, (CGFloat)p.value);
        }
        // A flat series still needs vertical headroom, otherwise the line sits on the axis.
        if (hi - lo < 1e-6) { hi += 1; lo -= 1; }
        double pad = (hi - lo) * 0.18;
        _minValue = (CGFloat)(lo - pad);
        _maxValue = (CGFloat)(hi + pad);
        if (_minValue < 0 && lo >= 0) _minValue = 0;
    }
    _accent = [ASDesign colorForLevel:ASAQILevelForValue(series.latest)];

    _lineLayer.strokeColor = _accent.CGColor;

    [self setNeedsLayout];
    [self setNeedsDisplay];

    if (animated && _points.count > 0) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        a.fromValue = @0.15;
        a.toValue = @1.0;
        a.duration = [ASDesign mediumDuration];
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_lineLayer addAnimation:a forKey:@"draw"];
    }
}

- (CGRect)plotRect
{
    CGFloat left = 36, right = 6, top = 8, bottom = 20;
    return CGRectMake(left, top,
                      MAX(1, CGRectGetWidth(self.bounds) - left - right),
                      MAX(1, CGRectGetHeight(self.bounds) - top - bottom));
}

- (CGPoint)pointForIndex:(NSUInteger)index
{
    CGRect r = [self plotRect];
    if (_points.count == 1) return CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    CGFloat x = r.origin.x + r.size.width * ((CGFloat)index / (CGFloat)(_points.count - 1));
    CGFloat t = (CGFloat)((_points[index].value - _minValue) / (_maxValue - _minValue));
    t = MAX(0, MIN(1, t));
    CGFloat y = r.origin.y + r.size.height * (1 - t);
    return CGPointMake(x, y);
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect r = [self plotRect];

    _bandLayer.frame = self.bounds;
    _gridLayer.frame = self.bounds;
    _fillGradientLayer.frame = self.bounds;
    _fillMaskLayer.frame = self.bounds;
    _lineLayer.frame = self.bounds;

    // Grid: four horizontal rules.
    UIBezierPath *grid = [UIBezierPath bezierPath];
    for (int i = 0; i <= 3; i++) {
        CGFloat y = r.origin.y + r.size.height * ((CGFloat)i / 3.0);
        [grid moveToPoint:CGPointMake(r.origin.x, y)];
        [grid addLineToPoint:CGPointMake(CGRectGetMaxX(r), y)];
    }
    _gridLayer.path = grid.CGPath;

    if (self.showsAQIBands) [self layoutAQIBandsInRect:r];

    if (_points.count == 0) {
        _lineLayer.path = NULL;
        _fillMaskLayer.path = NULL;
        _focusDot.opacity = 0;
        return;
    }

    UIBezierPath *line = [UIBezierPath bezierPath];
    UIBezierPath *fill = [UIBezierPath bezierPath];

    for (NSUInteger i = 0; i < _points.count; i++) {
        CGPoint p = [self pointForIndex:i];
        if (i == 0) {
            [line moveToPoint:p];
            [fill moveToPoint:CGPointMake(p.x, CGRectGetMaxY(r))];
            [fill addLineToPoint:p];
        } else {
            [line addLineToPoint:p];
            [fill addLineToPoint:p];
        }
    }
    CGPoint last = [self pointForIndex:_points.count - 1];
    [fill addLineToPoint:CGPointMake(last.x, CGRectGetMaxY(r))];
    [fill closePath];

    _lineLayer.path = line.CGPath;
    _fillMaskLayer.path = fill.CGPath;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fillGradientLayer.colors = @[(id)[_accent colorWithAlphaComponent:0.32].CGColor,
                                 (id)[_accent colorWithAlphaComponent:0.02].CGColor];
    [CATransaction commit];

    if (self.showsFocusPoint) {
        _focusDot.opacity = 1;
        _focusDot.backgroundColor = _accent.CGColor;
        _focusDot.bounds = CGRectMake(0, 0, 9, 9);
        _focusDot.cornerRadius = 4.5;
        _focusDot.position = last;
        // White halo so the dot stays visible over the area fill.
        _focusDot.shadowColor = [UIColor whiteColor].CGColor;
        _focusDot.shadowOpacity = 0.85;
        _focusDot.shadowRadius = 3;
        _focusDot.shadowOffset = CGSizeZero;
    } else {
        _focusDot.opacity = 0;
    }
}

/// Maps the 0-500 AQI scale onto the current value range so the bands align with the plot.
- (void)layoutAQIBandsInRect:(CGRect)r
{
    UIBezierPath *bands = [UIBezierPath bezierPath];
    NSArray<NSNumber *> *breaks = @[@0, @50, @100, @150, @200, @300, @500];
    for (NSUInteger i = 0; i + 1 < breaks.count; i++) {
        double lo = breaks[i].doubleValue, hi = breaks[i+1].doubleValue;
        if (hi < _minValue || lo > _maxValue) continue;
        CGFloat yTop = r.origin.y + r.size.height * (CGFloat)(1.0 - (MIN(hi, _maxValue) - _minValue) / (_maxValue - _minValue));
        CGFloat yBot = r.origin.y + r.size.height * (CGFloat)(1.0 - (MAX(lo, _minValue) - _minValue) / (_maxValue - _minValue));
        [bands appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(r.origin.x, yTop, r.size.width, yBot - yTop)]];
    }
    _bandLayer.path = bands.CGPath;
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx == NULL) return;

    CGRect r = [self plotRect];

    if (_points.count == 0) {
        return;
    }

    // Y labels: max, mid, min.
    NSArray<NSNumber *> *ticks = @[@(_maxValue), @((_maxValue + _minValue) / 2.0), @(_minValue)];
    NSDictionary *attrs = @{NSFontAttributeName: [ASDesign microFont],
                            NSForegroundColorAttributeName: [ASDesign tertiaryText]};
    for (NSUInteger i = 0; i < ticks.count; i++) {
        CGFloat t = (CGFloat)((ticks[i].doubleValue - _minValue) / (_maxValue - _minValue));
        CGFloat y = r.origin.y + r.size.height * (1 - MAX(0, MIN(1, t)));
        NSString *s = ASTrimNumber(ticks[i].doubleValue);
        CGSize size = [s sizeWithAttributes:attrs];
        CGFloat x = MAX(2, r.origin.x - size.width - 5);
        [s drawAtPoint:CGPointMake(x, y - size.height / 2) withAttributes:attrs];
    }

    // X labels: first, middle, last.
    if (_points.count >= 2) {
        NSArray<NSNumber *> *idxs = @[@0, @((_points.count - 1) / 2), @(_points.count - 1)];
        CGFloat lastX = -1000;
        for (NSUInteger i = 0; i < idxs.count; i++) {
            NSUInteger idx = idxs[i].unsignedIntegerValue;
            CGPoint p = [self pointForIndex:idx];
            NSString *s = [self labelForDate:_points[idx].date];
            CGSize size = [s sizeWithAttributes:attrs];
            CGFloat x = p.x - size.width / 2;
            if (x <= lastX + 6) continue;          // skip labels that would collide
            lastX = x;
            [s drawAtPoint:CGPointMake(x, CGRectGetMaxY(r) + 4) withAttributes:attrs];
        }
    }
}

- (NSString *)labelForDate:(NSDate *)date
{
    if (self.axisFormatter) return self.axisFormatter(date, self.range);
    return (self.range == ASRange7D || self.range == ASRange30D) ? ASShortDayString(date) : ASShortTimeString(date);
}

@end