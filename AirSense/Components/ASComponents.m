#import "Components/ASComponents.h"
#import "Utils/ASJSON.h"

#pragma mark - ASGlassCard

@implementation ASGlassCard {
    CALayer *_tintLayer;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _contentInset = [ASDesign cardPadding];
        self.backgroundColor = [UIColor clearColor];

        _glassView = [[UIView alloc] initWithFrame:CGRectZero];
        _glassView.userInteractionEnabled = NO;
        _glassView.translatesAutoresizingMaskIntoConstraints = NO;
        _glassView.layer.cornerCurve = kCACornerCurveContinuous;
        _glassView.layer.cornerRadius = [ASDesign cardRadius];
        _glassView.clipsToBounds = YES;
        [self addSubview:_glassView];
        [NSLayoutConstraint activateConstraints:@[
            [_glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];

        // The blur is a real UIVisualEffectView so it tracks system material behaviour.
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
        UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:blur];
        fx.translatesAutoresizingMaskIntoConstraints = NO;
        [_glassView addSubview:fx];
        [NSLayoutConstraint activateConstraints:@[
            [fx.topAnchor constraintEqualToAnchor:_glassView.topAnchor],
            [fx.bottomAnchor constraintEqualToAnchor:_glassView.bottomAnchor],
            [fx.leadingAnchor constraintEqualToAnchor:_glassView.leadingAnchor],
            [fx.trailingAnchor constraintEqualToAnchor:_glassView.trailingAnchor],
        ]];

        CALayer *tint = [CALayer layer];
        tint.backgroundColor = [ASDesign glassFill].CGColor;
        [_glassView.layer addSublayer:tint];
        tint.frame = _glassView.bounds;
        _tintLayer = tint;

        _borderGradient = [CAGradientLayer layer];
        _borderGradient.startPoint = CGPointMake(0, 0);
        _borderGradient.endPoint = CGPointMake(1, 1);
        _borderGradient.frame = _glassView.bounds;
        [_glassView.layer addSublayer:_borderGradient];
    }
    return self;
}

- (void)dealloc { _tintLayer = nil; }

- (void)setContentInset:(CGFloat)inset
{
    _contentInset = inset;
    [self setNeedsLayout];
}

- (instancetype)initWithEmphasis:(BOOL)emphasis
{
    if ((self = [self initWithFrame:CGRectZero])) {
        self->_emphasis = emphasis;
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CATransform3D cone = CATransform3DIdentity;
    cone.m34 = -1.0 / 900.0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.transform = cone;
    self.layer.transform = CATransform3DIdentity;

    _tintLayer.frame = _glassView.bounds;
    _tintLayer.cornerRadius = _glassView.layer.cornerRadius;
    _tintLayer.backgroundColor = (_emphasis ? [ASDesign glassFillStrong] : [ASDesign glassFill]).CGColor;

    _borderGradient.frame = _glassView.bounds;
    _borderGradient.cornerRadius = _glassView.layer.cornerRadius;
    UIColor *stroke = _emphasis ? [ASDesign glassHighlight] : [ASDesign glassStroke];
    _borderGradient.colors = @[(id)stroke.CGColor, (id)[UIColor clearColor].CGColor];

    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.10;
    self.layer.shadowRadius = 18;
    self.layer.shadowOffset = CGSizeMake(0, 8);
}

@end

#pragma mark - ASStatusBadge

@implementation ASStatusBadge

- (instancetype)initWithText:(NSString *)text color:(UIColor *)color
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.cornerRadius = 9;
        self.clipsToBounds = YES;

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [ASDesign microFont];
        _label.numberOfLines = 1;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3],
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        ]];
        [self applyText:text color:color];
    }
    return self;
}

- (void)applyText:(NSString *)text color:(UIColor *)color
{
    _label.text = text.uppercaseString;
    _label.textColor = color;
    _label.accessibilityLabel = text;
    self.backgroundColor = [color colorWithAlphaComponent:0.16];
    self.accessibilityLabel = text;
}

@end

#pragma mark - ASAQIRing

@implementation ASAQIRing {
    CAShapeLayer *_outer;
    CAShapeLayer *_inner;
    CAShapeLayer *_gloss;
    UILabel *_valueLabel;
    UILabel *_label;
    BOOL _animated;
}

+ (ASAQIRing *)ringWithMetricFont
{
    ASAQIRing *r = [[ASAQIRing alloc] initWithFrame:CGRectZero];
    return r;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        _animated = YES;

        _outer = [CAShapeLayer layer];
        _outer.fillColor = [UIColor clearColor].CGColor;
        _outer.strokeColor = [ASDesign separator].CGColor;
        _outer.lineWidth = 5;
        [self.layer addSublayer:_outer];

        _inner = [CAShapeLayer layer];
        _inner.fillColor = [UIColor clearColor].CGColor;
        _inner.strokeColor = [ASDesign goodColor].CGColor;
        _inner.lineWidth = 5;
        _inner.lineCap = kCALineCapRound;
        [self.layer addSublayer:_inner];

        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.textAlignment = NSTextAlignmentCenter;
        _valueLabel.font = [ASDesign displayFont];
        _valueLabel.textColor = [ASDesign primaryText];
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.7;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_valueLabel];

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [ASDesign captionFont];
        _label.textColor = [ASDesign secondaryText];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_valueLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-8],
            [_label.topAnchor constraintEqualToAnchor:_valueLabel.bottomAnchor constant:2],
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat line = 8.0;
    _outer.lineWidth = line;
    _inner.lineWidth = line;
    CGFloat inset = line / 2.0 + 2.0;
    CGRect r = CGRectInset(self.bounds, inset, inset);
    CGFloat side = MIN(CGRectGetWidth(r), CGRectGetHeight(r));
    CGFloat radius = MAX(10.0, side / 2.0);
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:center
                                                     radius:radius
                                                 startAngle:-M_PI_2
                                                   endAngle:-M_PI_2 + M_PI * 2
                                                  clockwise:YES];
    _outer.path = p.CGPath;
    _inner.path = p.CGPath;
    _outer.frame = self.layer.bounds;
    _inner.frame = self.layer.bounds;
}

- (void)setValue:(double)v level:(ASAQILevel)lvl animated:(BOOL)anim
{
    _valueLabel.text = isnan(v) ? @"—" : [NSString stringWithFormat:@"%.0f", v];
    _label.text = @"Chỉ số AQI";
    _inner.strokeColor = [ASDesign colorForLevel:lvl].CGColor;
    CGFloat pct = isnan(v) ? 0 : (CGFloat)ASClampDouble(v / 500.0, 0.0, 1.0);
    _inner.strokeEnd = 0;
    [CATransaction begin];
    [CATransaction setDisableActions:!anim];
    [CATransaction setCompletionBlock:^{ _inner.strokeEnd = pct; }];
    _inner.strokeEnd = pct;
    [CATransaction commit];
}

@end

#pragma mark - ASMetricCard

@implementation ASMetricCard {
    UIImageView *_iconView;
    UILabel *_nameLabel;
    UILabel *_valueLabel;
    UILabel *_noteLabel;
    UIView *_track;
    UIView *_fill;
    NSLayoutConstraint *_fillWidth;
    UIStackView *_rootStack;
}
@synthesize badge = _badge;

- (instancetype)initWithReading:(ASReading *)reading
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [ASDesign glassFill];
        self.layer.cornerRadius = 16;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [ASDesign glassStroke].CGColor;
        self.clipsToBounds = YES;

        // --- Top row: icon + name leading, badge trailing ---
        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.tintColor = [ASDesign secondaryText];
        icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                              weight:UIImageSymbolWeightSemibold];
        icon.tag = 9001;
        _iconView = icon;

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = [ASDesign captionFont];
        _nameLabel.textColor = [ASDesign secondaryText];
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.8;
        [_nameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh
                                     forAxis:UILayoutConstraintAxisHorizontal];

        _badge = [[ASStatusBadge alloc] initWithText:@"—" color:[ASDesign secondaryText]];

        // spacer pushes the badge to the trailing edge, preventing any chance of
        // a wide pill ("BÌNH THƯỜNG", "Vượt ngưỡng") colliding with the name.
        UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
        [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow
                                 forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *topRow = [[UIStackView alloc]
            initWithArrangedSubviews:@[icon, _nameLabel, spacer, _badge]];
        topRow.axis = UILayoutConstraintAxisHorizontal;
        topRow.alignment = UIStackViewAlignmentCenter;
        topRow.spacing = 6;

        // --- Value (row 2) ---
        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.font = [ASDesign metricFont];
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.6;

        // --- Note (row 3) ---
        _noteLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _noteLabel.font = [ASDesign microFont];
        _noteLabel.textColor = [ASDesign tertiaryText];
        _noteLabel.numberOfLines = 1;

        // --- Threshold bar (row 4) ---
        _track = [[UIView alloc] initWithFrame:CGRectZero];
        _track.backgroundColor = [ASDesign separator];
        _track.layer.cornerRadius = 2.0;
        _track.layer.cornerCurve = kCACornerCurveContinuous;

        _fill = [[UIView alloc] initWithFrame:CGRectZero];
        _fill.backgroundColor = [ASDesign goodColor];
        _fill.layer.cornerRadius = 2.0;
        _fill.layer.cornerCurve = kCACornerCurveContinuous;
        _fill.layer.masksToBounds = YES;
        [_track addSubview:_fill];

        [NSLayoutConstraint activateConstraints:@[
            [_fill.topAnchor constraintEqualToAnchor:_track.topAnchor],
            [_fill.bottomAnchor constraintEqualToAnchor:_track.bottomAnchor],
            [_fill.leadingAnchor constraintEqualToAnchor:_track.leadingAnchor],
            [_fill.heightAnchor constraintEqualToConstant:4],
        ]];
        _fillWidth = [_fill.widthAnchor constraintEqualToAnchor:_track.widthAnchor multiplier:0.001];

        // --- Vertical stack ---
        [icon.widthAnchor constraintEqualToConstant:20].active = YES;
        [icon.heightAnchor constraintEqualToConstant:20].active = YES;
        [_track.heightAnchor constraintEqualToConstant:4].active = YES;

        _rootStack = [[UIStackView alloc]
            initWithArrangedSubviews:@[topRow, _valueLabel, _noteLabel, _track]];
        _rootStack.axis = UILayoutConstraintAxisVertical;
        _rootStack.spacing = 6;
        _rootStack.alignment = UIStackViewAlignmentFill;
        _rootStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_rootStack];

        [NSLayoutConstraint activateConstraints:@[
            [_rootStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [_rootStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_rootStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_rootStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        ]];
        _fillWidth.active = YES;

        self.isAccessibilityElement = YES;
        [self applyReading:reading];
    }
    return self;
}

- (void)applyReading:(ASReading *)reading
{
    _metricKey = [reading.key copy];
    _nameLabel.text = reading.label;
    _iconView.image = [UIImage systemImageNamed:reading.symbol];
    _valueLabel.textColor = [ASDesign primaryText];

    if (reading.hasValue) {
        _valueLabel.text = ASTrimNumber(reading.value.doubleValue);
        if (reading.unit.length) {
            NSAttributedString *s = [[NSAttributedString alloc] initWithString:
                [NSString stringWithFormat:@"%@ %@", _valueLabel.text, reading.unit]
                attributes:@{NSFontAttributeName: [ASDesign metricFont],
                             NSForegroundColorAttributeName: [ASDesign primaryText]}];
            NSMutableAttributedString *m = [s mutableCopy];
            NSRange unitRange = [s.string rangeOfString:reading.unit];
            if (unitRange.location != NSNotFound) {
                [m addAttributes:@{NSFontAttributeName: [ASDesign microFont],
                                   NSForegroundColorAttributeName: [ASDesign tertiaryText]}
                           range:unitRange];
            }
            _valueLabel.attributedText = m;
        }
    } else {
        _valueLabel.attributedText = [[NSAttributedString alloc] initWithString:@"--"
            attributes:@{NSFontAttributeName: [ASDesign metricFont],
                         NSForegroundColorAttributeName: [ASDesign tertiaryText]}];
    }

    ASAQILevel lvl = reading.level;
    if (reading.alerts) {
        [_badge applyText:@"Vượt ngưỡng" color:[ASDesign dangerColor]];
    } else if (lvl != ASAQILevelUnknown) {
        [_badge applyText:ASAQILevelShortLabel(lvl) color:[ASDesign colorForLevel:lvl]];
    } else if (!reading.hasValue) {
        [_badge applyText:@"Lỗi" color:[ASDesign tertiaryText]];
    } else {
        [_badge applyText:@"—" color:[ASDesign tertiaryText]];
    }

    _noteLabel.text = reading.note.length ? reading.note
        : (reading.threshold > 0 ? [NSString stringWithFormat:@"Ngưỡng %@ %@",
                                     ASTrimNumber(reading.threshold), reading.unit ?: @""] : @"");

    BOOL canBar = reading.hasValue && reading.threshold > 0 && !isnan(reading.threshold);
    _track.hidden = !canBar;
    if (canBar) {
        _fill.backgroundColor = [ASDesign colorForLevel:lvl];
        // Full bar = 2x threshold, so reaching the threshold lands at the halfway mark.
        CGFloat ratio = ASClampDouble(reading.ratio / 2.0, 0.001, 1.0);
        _fillWidth.active = NO;
        _fillWidth = [_fill.widthAnchor constraintEqualToAnchor:_track.widthAnchor multiplier:ratio];
        _fillWidth.active = YES;
    }

    _valueLabel.accessibilityLabel = nil;
    self.accessibilityLabel = reading.hasValue
        ? [NSString stringWithFormat:@"%@: %@ %@, %@",
           reading.label, ASTrimNumber(reading.value.doubleValue), reading.unit,
           ASAQILevelShortLabel(lvl)]
        : [NSString stringWithFormat:@"%@: không có dữ liệu", reading.label];
}

@end

#pragma mark - ASKeyValueRow

@implementation ASKeyValueRow {
    UILabel *_labelLabel;
    UILabel *_valueLabel;
    UIImageView *_icon;
}

- (instancetype)initWithLabel:(NSString *)label value:(NSString *)value
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [UIColor clearColor];

        _icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.tintColor = [ASDesign tertiaryText];
        _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:13
                                                                                               weight:UIImageSymbolWeightMedium];

        _labelLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _labelLabel.font = [ASDesign bodyFont];
        _labelLabel.textColor = [ASDesign secondaryText];
        _labelLabel.adjustsFontSizeToFitWidth = YES;
        _labelLabel.minimumScaleFactor = 0.8;

        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.font = [ASDesign headlineFont];
        _valueLabel.textColor = [ASDesign primaryText];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.7;
        _valueLabel.numberOfLines = 1;

        _stack = [[UIStackView alloc] initWithArrangedSubviews:@[_icon, _labelLabel, _valueLabel]];
        _stack.axis = UILayoutConstraintAxisHorizontal;
        _stack.alignment = UIStackViewAlignmentCenter;
        _stack.spacing = 8;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];

        [_icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_valueLabel setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
        [_labelLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-11],
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_icon.widthAnchor constraintEqualToConstant:18],
            [_icon.heightAnchor constraintEqualToConstant:18],
        ]];

        [self applyLabel:label value:value valueColor:nil];
        self.isAccessibilityElement = YES;
    }
    return self;
}

- (void)applyLabel:(NSString *)label value:(NSString *)value valueColor:(UIColor *)color
{
    _labelLabel.text = label;
    _valueLabel.text = value ?: @"--";
    _valueLabel.textColor = color ?: [ASDesign primaryText];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", label, _valueLabel.text];
}

- (void)setSymbolName:(NSString *)symbol
{
    _icon.image = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
    _icon.hidden = symbol.length == 0;
    [_icon.widthAnchor constraintEqualToConstant:symbol.length ? 18 : 0].active = YES;
}

@end

#pragma mark - ASLoadingView

@implementation ASLoadingView

- (instancetype)initWithMessage:(NSString *)message
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [UIColor clearColor];

        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        spinner.color = [ASDesign secondaryText];
        [spinner startAnimating];
        [self addSubview:spinner];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = message;
        label.font = [ASDesign bodyFont];
        label.textColor = [ASDesign secondaryText];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [spinner.topAnchor constraintEqualToAnchor:self.topAnchor],
            [label.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:12],
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
            [label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
            [label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

@end

#pragma mark - ASSkeletonBlock

@implementation ASSkeletonBlock {
    CAGradientLayer *_shimmer;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _skeletonHeight = 18;
        _skeletonRadius = 8;
        self.backgroundColor = [ASDesign separator];
        self.layer.cornerRadius = _skeletonRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _shimmer = [CAGradientLayer layer];
        _shimmer.startPoint = CGPointMake(0, 0.5);
        _shimmer.endPoint = CGPointMake(1, 0.5);
        _shimmer.colors = @[
            (id)[UIColor clearColor].CGColor,
            (id)[[UIColor whiteColor] colorWithAlphaComponent:0.35].CGColor,
            (id)[UIColor clearColor].CGColor,
        ];
        _shimmer.locations = @[@0, @0.5, @1];
        [self.layer addSublayer:_shimmer];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.layer.cornerRadius = _skeletonRadius;
    _shimmer.frame = CGRectMake(0, 0, self.bounds.size.width * 2, self.bounds.size.height);
}

- (void)startShimmering
{
    if ([_shimmer animationForKey:@"shimmer"]) return;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    a.fromValue = @(-self.bounds.size.width);
    a.toValue = @(self.bounds.size.width);
    a.duration = 1.3;
    a.repeatCount = HUGE_VALF;
    [_shimmer addAnimation:a forKey:@"shimmer"];
}

- (void)stopShimmering
{
    [_shimmer removeAnimationForKey:@"shimmer"];
}

@end

#pragma mark - ASEmptyStateView

@implementation ASEmptyStateView {
    UIImageView *_icon;
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    UIButton *_button;
}

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title message:(NSString *)message
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [UIColor clearColor];

        _icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _icon.image = [UIImage systemImageNamed:symbol];
        _icon.tintColor = [ASDesign tertiaryText];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:38
                                                                                               weight:UIImageSymbolWeightRegular];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_icon];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [ASDesign headlineFont];
        _titleLabel.textColor = [ASDesign primaryText];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 0;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _messageLabel.font = [ASDesign bodyFont];
        _messageLabel.textColor = [ASDesign secondaryText];
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.numberOfLines = 0;
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_messageLabel];

        _button = [ASGlassButton primaryButtonWithTitle:@"" symbol:nil];
        [_button addTarget:self action:@selector(didTapAction) forControlEvents:UIControlEventTouchUpInside];
        _button.hidden = YES;
        [self addSubview:_button];

        [NSLayoutConstraint activateConstraints:@[
            [_icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_icon.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_icon.widthAnchor constraintEqualToConstant:52],
            [_icon.heightAnchor constraintEqualToConstant:52],

            [_titleLabel.topAnchor constraintEqualToAnchor:_icon.bottomAnchor constant:14],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],

            [_messageLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:7],
            [_messageLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [_messageLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],

            [_button.topAnchor constraintEqualToAnchor:_messageLabel.bottomAnchor constant:18],
            [_button.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        [self applyTitle:title message:message];
    }
    return self;
}

- (void)applyTitle:(NSString *)title message:(NSString *)message
{
    _titleLabel.text = title;
    _messageLabel.text = message;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", title, message];
}

- (void)setActionTitle:(NSString *)title
{
    _button.hidden = title.length == 0;
    [_button setTitle:title forState:UIControlStateNormal];
}

- (void)didTapAction
{
    if (self.actionHandler) self.actionHandler();
}

@end

#pragma mark - ASTapProxy

/// Forwards a tap to a target without the handler block retaining the view that owns it.
@interface ASTapProxy : NSObject
- (instancetype)initWithTarget:(id)target;
- (void)fire;
@end

@implementation ASTapProxy {
    __weak id _target;
}
- (instancetype)initWithTarget:(id)target
{
    if ((self = [super init])) _target = target;
    return self;
}
- (void)fire
{
    if ([_target respondsToSelector:@selector(fireRetry)]) {
        [_target performSelector:@selector(fireRetry)];
    }
}
@end

#pragma mark - ASErrorStateView

@implementation ASErrorStateView {
    ASEmptyStateView *_inner;
    ASTapProxy *_innerTarget;
}

- (void)fireRetry
{
    if (self.retryHandler) self.retryHandler();
}

- (instancetype)initWithMessage:(NSString *)message retryTitle:(NSString *)retryTitle
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [UIColor clearColor];
        _inner = [[ASEmptyStateView alloc] initWithSymbol:@"exclamationmark.triangle"
                                                   title:@"Đã xảy ra lỗi"
                                                 message:message];
        _inner.translatesAutoresizingMaskIntoConstraints = NO;
        __weak typeof(self) weakSelf = self;
        _inner.actionHandler = ^{ if (weakSelf.retryHandler) weakSelf.retryHandler(); };
        [self addSubview:_inner];
        _innerTarget = [[ASTapProxy alloc] initWithTarget:self];

        [NSLayoutConstraint activateConstraints:@[
            [_inner.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_inner.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_inner.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_inner.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
        [self applyMessage:message retryTitle:retryTitle];
    }
    return self;
}

- (void)applyMessage:(NSString *)message retryTitle:(NSString *)retryTitle
{
    [_inner applyTitle:@"Đã xảy ra lỗi" message:message];
    [_inner setActionTitle:retryTitle];
}

@end

#pragma mark - ASStatusBanner

@implementation ASStatusBanner {
    UILabel *_label;
    UIImageView *_icon;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 14;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.hidden = YES;

        _icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:12
                                                                                               weight:UIImageSymbolWeightBold];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_icon];

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.font = [ASDesign captionFont];
        _label.numberOfLines = 2;
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.85;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:16],
            [_icon.heightAnchor constraintEqualToConstant:16],
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:9],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-9],
            [_label.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:8],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        ]];
    }
    return self;
}

- (void)applyText:(NSString *)text symbol:(NSString *)symbol color:(UIColor *)color
{
    _label.text = text;
    _label.textColor = color;
    _icon.image = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
    self.backgroundColor = [color colorWithAlphaComponent:0.15];
    self.accessibilityLabel = text;
    self.hidden = NO;
}

- (void)hide { self.hidden = YES; }

@end

#pragma mark - ASGlassButton

@implementation ASGlassButton

/// iOS 26 ships UIButtonConfiguration.glassButtonConfiguration, but the deployment target is
/// iOS 16, so the glass surface is assembled from a blur view behind a tinted config.
+ (ASGlassButton *)baseButtonWithTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint filled:(BOOL)filled
{
    UIButtonConfiguration *cfg = filled ? [UIButtonConfiguration filledButtonConfiguration]
                                         : [UIButtonConfiguration grayButtonConfiguration];
    cfg.title = title;
    UIColor *fg = tint ?: [ASDesign primaryText];
    cfg.baseForegroundColor = fg;
    cfg.baseBackgroundColor = [fg colorWithAlphaComponent:filled ? 0.22 : 0.12];
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(11, 18, 11, 18);
    if (@available(iOS 15.0, *)) {
        cfg.imagePlacement = NSDirectionalRectEdgeLeading;
    }
    if (symbol.length) {
        cfg.image = [UIImage systemImageNamed:symbol];
        cfg.imagePadding = 7;
        cfg.preferredSymbolConfigurationForImage =
            [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    }

    ASGlassButton *b = [ASGlassButton buttonWithConfiguration:cfg primaryAction:nil];
    b.titleLabel.font = [ASDesign headlineFont];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.8;

    // Soft drop shadow so the button reads as a floating capsule.
    b.layer.shadowColor = [UIColor blackColor].CGColor;
    b.layer.shadowOpacity = 0.14;
    b.layer.shadowRadius = 10;
    b.layer.shadowOffset = CGSizeMake(0, 4);
    return b;
}

+ (instancetype)primaryButtonWithTitle:(NSString *)title symbol:(NSString *)symbol
{
    // Solid-accent capsule: the colour comes from ASDesign so it tracks the
    // ambient theme (system green for light, lighter-tinted on dark).
    return [self baseButtonWithTitle:title symbol:symbol tint:[ASDesign primaryActionTint] filled:YES];
}

+ (instancetype)secondaryButtonWithTitle:(NSString *)title symbol:(NSString *)symbol
{
    return [self baseButtonWithTitle:title symbol:symbol tint:[ASDesign secondaryText] filled:NO];
}

+ (instancetype)dangerButtonWithTitle:(NSString *)title symbol:(NSString *)symbol
{
    return [self baseButtonWithTitle:title symbol:symbol tint:[ASDesign dangerColor] filled:YES];
}

- (void)setLoading:(BOOL)loading
{
    if (loading) {
        [self setTitle:@"Đang gửi…" forState:UIControlStateNormal];
        self.enabled = NO;
    } else {
        self.enabled = YES;
    }
}

@end

#pragma mark - ASSegmentedControl

@implementation ASSegmentedControl {
    NSMutableArray<UIButton *> *_buttons;
    UIView *_selection;
    UIStackView *_stack;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [ASDesign separator];
        self.layer.cornerRadius = 13;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        _selectedIndex = 0;
        _buttons = [NSMutableArray array];

        _selection = [[UIView alloc] initWithFrame:CGRectZero];
        _selection.backgroundColor = [ASDesign glassFillStrong];
        _selection.layer.cornerRadius = 11;
        _selection.layer.cornerCurve = kCACornerCurveContinuous;
        _selection.layer.shadowColor = [UIColor blackColor].CGColor;
        _selection.layer.shadowOpacity = 0.10;
        _selection.layer.shadowRadius = 5;
        _selection.layer.shadowOffset = CGSizeZero;
        [self addSubview:_selection];
    }
    return self;
}

- (void)setTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)index
{
    _titles = [titles copy];
    for (UIButton *b in _buttons) { [b removeFromSuperview]; }
    [_buttons removeAllObjects];
    if (_stack) {
        [_stack removeFromSuperview];
        _stack = nil;
    }
    _selectedIndex = MAX(0, MIN(index, (NSInteger)titles.count - 1));

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    _stack = stack;

    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = (NSInteger)i;
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:[ASDesign secondaryText] forState:UIControlStateNormal];
        b.titleLabel.font = [ASDesign captionFont];
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.7;
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [b addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:b];
        [_buttons addObject:b];
    }

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
    ]];

    [self updateAppearanceAnimated:NO];
}

- (void)setSelectedIndexSilently:(NSInteger)index
{
    _selectedIndex = index;
    [self updateAppearanceAnimated:NO];
}

- (void)setSelectedIndex:(NSInteger)index
{
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    [self updateAppearanceAnimated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)updateAppearanceAnimated:(BOOL)animated
{
    if (_buttons.count == 0) return;
    void (^apply)(void) = ^{
        BOOL any = (self->_selectedIndex >= 0);
        for (NSUInteger i = 0; i < _buttons.count; i++) {
            BOOL on = any && (NSInteger)i == self->_selectedIndex;
            [_buttons[i] setTitleColor:on ? [ASDesign primaryText] : [ASDesign secondaryText]
                             forState:UIControlStateNormal];
            _buttons[i].titleLabel.font = on ? [ASDesign headlineFont] : [ASDesign captionFont];
        }
        UIButton *sel = nil;
        if (any) sel = _buttons[MAX(0, MIN(self->_selectedIndex, (NSInteger)_buttons.count - 1))];
        if (sel && !CGRectIsEmpty(sel.bounds)) {
            self->_selection.frame = [self convertRect:sel.bounds fromView:sel];
        } else {
            self->_selection.frame = CGRectZero;
        }
    };
    if (animated) {
        [UIView animateWithDuration:[ASDesign quickDuration]
                              delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                           animations:apply completion:nil];
    } else {
        apply();
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self updateAppearanceAnimated:NO];
}

- (void)buttonTapped:(UIButton *)sender
{
    NSInteger index = sender.tag;
    if (index == _selectedIndex) return;
    [ASDesign hapticLight];
    self.selectedIndex = index;
}

@end
