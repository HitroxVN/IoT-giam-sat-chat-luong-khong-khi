// ASRootViewController — Custom glass tab bar.
// A plain UITabBarController gets the stock opaque bar; this builds a floating
// capsule bar with a blur, a sliding selection pill and a badge on Alerts.

#import "Application/ASRootViewController.h"
#import "Components/ASComponents.h"
#import "Design/ASDesign.h"
#import "Services/ASMonitor.h"
#import "UI/ASDashboardViewController.h"
#import "UI/ASHistoryViewController.h"
#import "UI/ASAlertsViewController.h"
#import "UI/ASSettingsViewController.h"
#import "UI/ASAirQualityViewController.h"

/// Bar height (60) + its 8pt gap + a little breathing room.
static const CGFloat kASTabBarReservedHeight = 76.0;

@interface ASTabBarItem : NSObject
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *symbol;
@property (nonatomic, copy)   NSString *selectedSymbol;
@property (nonatomic, strong) UINavigationController *controller;
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@end

@implementation ASTabBarItem
@end

@implementation ASRootViewController {
    NSArray<ASTabBarItem *> *_items;
    UIView *_bar;
    UIView *_pill;
    NSInteger _selectedIndex;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    [self buildTabs];
    [self buildBar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(monitorDidUpdate)
                                                 name:ASMonitorDidUpdateNotification
                                               object:nil];
    [self applyTheme];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applyTheme];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous
{
    [super traitCollectionDidChange:previous];
    if (self.traitCollection.userInterfaceStyle != previous.userInterfaceStyle) {
        [self applyTheme];
    }
}

#pragma mark - Build

- (ASTabBarItem *)itemWithTitle:(NSString *)title
                        symbol:(NSString *)symbol
                selectedSymbol:(NSString *)selectedSymbol
                    controller:(UIViewController *)controller
{
    ASTabBarItem *item = [[ASTabBarItem alloc] init];
    item.title = title;
    item.symbol = symbol;
    item.selectedSymbol = selectedSymbol;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    item.controller = nav;
    nav.navigationBarHidden = YES;   // the screen draws its own large title
    // The floating bar floats over the content, so each screen reserves room for it.
    nav.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, kASTabBarReservedHeight, 0);
    return item;
}

- (void)buildTabs
{
    ASDashboardViewController *dashboard = [[ASDashboardViewController alloc] init];
    dashboard.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    _items = @[
        [self itemWithTitle:@"Tổng quan" symbol:@"square.grid.2x2" selectedSymbol:@"square.grid.2x2.fill" controller:dashboard],
        [self itemWithTitle:@"Lịch sử"  symbol:@"chart.xyaxis.line" selectedSymbol:@"chart.xyaxis.line" controller:[[ASHistoryViewController alloc] init]],
        [self itemWithTitle:@"Cảnh báo" symbol:@"bell" selectedSymbol:@"bell.fill" controller:[[ASAlertsViewController alloc] init]],
        [self itemWithTitle:@"Phân tích" symbol:@"aqi.medium" selectedSymbol:@"aqi.medium" controller:[[ASAirQualityViewController alloc] init]],
        [self itemWithTitle:@"Cài đặt" symbol:@"gearshape" selectedSymbol:@"gearshape.fill" controller:[[ASSettingsViewController alloc] init]],
    ];

    [self addChildViewController:_items[0].controller];
    _items[0].controller.view.frame = self.view.bounds;
    _items[0].controller.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_items[0].controller.view];
    [_items[0].controller didMoveToParentViewController:self];
    _selectedIndex = 0;
}

- (void)buildBar
{
    _bar = [[UIView alloc] initWithFrame:CGRectZero];
    _bar.translatesAutoresizingMaskIntoConstraints = NO;
    _bar.backgroundColor = [ASDesign glassFillStrong];
    _bar.layer.cornerRadius = 30;
    _bar.layer.cornerCurve = kCACornerCurveContinuous;
    _bar.layer.borderWidth = 1;
    _bar.layer.borderColor = [ASDesign glassStroke].CGColor;
    _bar.layer.shadowColor = [UIColor blackColor].CGColor;
    _bar.layer.shadowOpacity = 0.16;
    _bar.layer.shadowRadius = 20;
    _bar.layer.shadowOffset = CGSizeMake(0, 8);
    _bar.clipsToBounds = NO;
    [self.view addSubview:_bar];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.userInteractionEnabled = NO;
    blur.layer.cornerRadius = 30;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [_bar addSubview:blur];
    [NSLayoutConstraint activateConstraints:@[
        [blur.topAnchor constraintEqualToAnchor:_bar.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:_bar.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:_bar.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:_bar.trailingAnchor],
    ]];

    _pill = [[UIView alloc] initWithFrame:CGRectZero];
    _pill.backgroundColor = [[ASDesign primaryText] colorWithAlphaComponent:0.10];
    _pill.layer.cornerRadius = 22;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    _pill.translatesAutoresizingMaskIntoConstraints = YES;
    [_bar addSubview:_pill];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_bar addSubview:stack];

    for (NSUInteger i = 0; i < _items.count; i++) {
        ASTabBarItem *item = _items[i];

        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = (NSInteger)i;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.accessibilityLabel = item.title;
        button.accessibilityTraits = UIAccessibilityTraitButton;
        [button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];

        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.image = [UIImage systemImageNamed:item.symbol];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.tintColor = [ASDesign secondaryText];
        icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:19
                                                                                               weight:UIImageSymbolWeightMedium];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [button addSubview:icon];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = item.title;
        label.font = [ASDesign microFont];
        label.textColor = [ASDesign secondaryText];
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.75;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [button addSubview:label];

        item.button = button;
        item.icon = icon;
        item.label = label;

        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
            [icon.topAnchor constraintEqualToAnchor:button.topAnchor constant:9],
            [icon.widthAnchor constraintEqualToConstant:24],
            [icon.heightAnchor constraintEqualToConstant:24],
            [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:3],
            [label.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:1],
            [label.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-1],
            [label.bottomAnchor constraintLessThanOrEqualToAnchor:button.bottomAnchor constant:-7],
        ]];

        [stack addArrangedSubview:button];
    }

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_bar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [_bar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [_bar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [_bar.heightAnchor constraintEqualToConstant:60],

        [stack.topAnchor constraintEqualToAnchor:_bar.topAnchor constant:2],
        [stack.bottomAnchor constraintEqualToAnchor:_bar.bottomAnchor constant:-2],
        [stack.leadingAnchor constraintEqualToAnchor:_bar.leadingAnchor constant:4],
        [stack.trailingAnchor constraintEqualToAnchor:_bar.trailingAnchor constant:-4],
    ]];

    [self layoutPillAnimated:NO];
}

/// Screens sit above the bar so nothing is hidden behind it.
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    for (ASTabBarItem *item in _items) {
        item.controller.view.frame = self.view.bounds;
    }
    [self layoutPillAnimated:NO];
}

- (void)layoutPillAnimated:(BOOL)animated
{
    if (_items.count == 0 || _items[_selectedIndex].button == nil) return;
    UIButton *btn = _items[_selectedIndex].button;
    if (CGRectIsEmpty(btn.bounds)) return;
    CGRect target = [_bar convertRect:btn.bounds fromView:btn];
    target = CGRectInset(target, 3, 4);
    void (^apply)(void) = ^{ self->_pill.frame = target; };
    if (animated) {
        [UIView animateWithDuration:[ASDesign quickDuration]
                              delay:0 usingSpringWithDamping:[ASDesign springDamping]
              initialSpringVelocity:0.6 options:UIViewAnimationOptionBeginFromCurrentState
                           animations:apply completion:nil];
    } else {
        apply();
    }
}

#pragma mark - State

- (void)applyTheme
{
    _bar.backgroundColor = [ASDesign glassFillStrong];
    _bar.layer.borderColor = [ASDesign glassStroke].CGColor;

    for (NSUInteger i = 0; i < _items.count; i++) {
        ASTabBarItem *item = _items[i];
        BOOL on = ((NSInteger)i == _selectedIndex);
        item.icon.image = [UIImage systemImageNamed:on ? item.selectedSymbol : item.symbol];
        item.icon.tintColor = on ? [ASDesign primaryText] : [ASDesign secondaryText];
        item.label.textColor = on ? [ASDesign primaryText] : [ASDesign secondaryText];
        item.button.accessibilityTraits = on ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected
                                             : UIAccessibilityTraitButton;
        item.button.accessibilityIdentifier = item.title;
    }
    _pill.backgroundColor = [[ASDesign primaryText] colorWithAlphaComponent:0.10];
}

- (void)monitorDidUpdate
{
    // Badge the Alerts tab while the device reports a condition.
    ASTabBarItem *alerts = _items.count > 2 ? _items[2] : nil;
    if (alerts == nil) return;
    BOOL danger = [ASMonitor shared].snapshot.alert.danger;
    alerts.label.text = danger ? @"Cảnh báo" : alerts.title;
    if (danger) {
        alerts.icon.tintColor = [ASDesign dangerColor];
        alerts.button.accessibilityLabel = @"Cảnh báo, đang có cảnh báo";
    } else {
        alerts.icon.tintColor = ((NSInteger)[_items indexOfObject:alerts] == _selectedIndex)
            ? [ASDesign primaryText] : [ASDesign secondaryText];
        alerts.button.accessibilityLabel = alerts.title;
    }
}

#pragma mark - Actions

- (void)tabTapped:(UIButton *)sender
{
    NSInteger index = sender.tag;
    if (index == _selectedIndex || index < 0 || index >= (NSInteger)_items.count) return;

    [ASDesign hapticLight];
    UIViewController *incoming = _items[index].controller;

    [self addChildViewController:incoming];
    incoming.view.frame = self.view.bounds;
    incoming.view.alpha = 0;
    [self.view insertSubview:incoming.view belowSubview:_bar];
    [incoming didMoveToParentViewController:self];

    UIViewController *outgoing = _items[_selectedIndex].controller;
    _selectedIndex = index;

    [UIView animateWithDuration:[ASDesign quickDuration]
                          delay:0 options:UIViewAnimationOptionCurveEaseInOut
                       animations:^{
        incoming.view.alpha = 1;
        outgoing.view.alpha = 0;
    } completion:^(BOOL finished) {
        [outgoing willMoveToParentViewController:nil];
        [outgoing.view removeFromSuperview];
        [outgoing removeFromParentViewController];
    }];

    [self applyTheme];
    [self layoutPillAnimated:YES];
}

@end