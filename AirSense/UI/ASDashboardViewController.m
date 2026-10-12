#import "UI/ASDashboardViewController.h"
#import "Components/ASComponents.h"
#import "Design/ASDesign.h"
#import "Services/ASMonitor.h"
#import "Services/ASSettings.h"
#import "Utils/ASJSON.h"
#import "UI/ASAirQualityViewController.h"
#import "UI/ASSettingsViewController.h"

@implementation ASDashboardViewController {
    CAGradientLayer *_bgGradient;
    UIScrollView *_scroll;
    UIStackView *_content;
    ASStatusBanner *_banner;
    ASLoadingView *_loading;
    ASErrorStateView *_error;
    ASEmptyStateView *_empty;

    ASAQIRing *_ring;
    UILabel *_headlineLabel;
    UILabel *_updatedLabel;
    UILabel *_aqiSourceLabel;

    ASGlassCard *_deviceCard;
    NSMutableArray<ASKeyValueRow *> *_deviceValueLabels;

    UIStackView *_metricGrid;
    NSMutableArray<ASMetricCard *> *_metricCards;
    UIStackView *_alertStack;
    ASGlassCard *_alertCard;
    NSMutableArray<NSString *> *_deviceRowLabels;
    NSInteger _lastColumnCount;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"AirSense";
    self.view.backgroundColor = [UIColor clearColor];
    [self buildBackground];
    [self buildContent];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(monitorDidUpdate)
                                                 name:ASMonitorDidUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityDidChange)
                                                 name:ASMonitorDidReachabilityChangeNotification
                                               object:nil];

    [self monitorDidUpdate];
    [[ASMonitor shared] refresh];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self monitorDidUpdate];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous
{
    [super traitCollectionDidChange:previous];
    if (self.traitCollection.userInterfaceStyle != previous.userInterfaceStyle) {
        [self applyBackground];
    }
}

#pragma mark - Build

- (void)buildBackground
{
    _bgGradient = [ASDesign ambientBackgroundForLevel:ASAQILevelUnknown];
    _bgGradient.frame = self.view.bounds;
    [self.view.layer insertSublayer:_bgGradient atIndex:0];
}

- (void)applyBackground
{
    ASSnapshot *s = [ASMonitor shared].snapshot;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _bgGradient.colors = @[(id)[ASDesign ambientTopForLevel:s ? s.aqiLevel : ASAQILevelUnknown].CGColor,
                           (id)[ASDesign ambientBottomForLevel:s ? s.aqiLevel : ASAQILevelUnknown].CGColor];
    [CATransaction commit];
}

- (UIView *)sectionHeaderWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action
{
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 6;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.image = [UIImage systemImageNamed:symbol];
    icon.tintColor = [ASDesign secondaryText];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:14
                                                                                          weight:UIImageSymbolWeightSemibold];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:18].active = YES;
    [icon.heightAnchor constraintEqualToConstant:18].active = YES;
    [row addArrangedSubview:icon];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = title;
    label.font = [ASDesign headlineFont];
    label.textColor = [ASDesign primaryText];
    [row addArrangedSubview:label];

    if (action) {
        UIButton *more = [ASGlassButton secondaryButtonWithTitle:@"Chi tiết" symbol:@"chevron.right"];
        [more setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [more addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:more];
    }
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 0, 0, 0);
    return row;
}

- (void)buildContent
{
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.alwaysBounceVertical = YES;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
    _scroll.refreshControl = rc;
    [self.view addSubview:_scroll];

    _content = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _content.axis = UILayoutConstraintAxisVertical;
    _content.spacing = [ASDesign stackSpacing];
    _content.translatesAutoresizingMaskIntoConstraints = NO;
    _content.layoutMarginsRelativeArrangement = YES;
    _content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, [ASDesign cardInset], 28, [ASDesign cardInset]);
    [_scroll addSubview:_content];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],

        [_content.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
        [_content.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
        [_content.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
        [_content.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
        [_content.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor],
    ]];

    _banner = [[ASStatusBanner alloc] initWithFrame:CGRectZero];
    [_content addArrangedSubview:_banner];

    [self buildAQICard];
    [self buildAlertCard];
    [self buildMetricSection];
    [self buildDeviceCard];

    // State views are overlaid on the scroll view, not stacked, so they stay centred.
    _loading = [[ASLoadingView alloc] initWithMessage:@"Đang đọc dữ liệu từ ESP32…"];
    _loading.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loading];

    _error = [[ASErrorStateView alloc] initWithMessage:@"Không tải được dữ liệu." retryTitle:@"Thử lại"];
    _error.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _error.retryHandler = ^{ [[ASMonitor shared] refresh]; };
    [self.view addSubview:_error];

    _empty = [[ASEmptyStateView alloc] initWithSymbol:@"antenna.radiowaves.left.and.right.slash"
                                              title:@"Chưa cấu hình thiết bị"
                                            message:@"Nhập IP của ESP32 trong Cài đặt để bắt đầu theo dõi chất lượng không khí."];
    _empty.translatesAutoresizingMaskIntoConstraints = NO;
    _empty.actionHandler = ^{ [weakSelf openSettings]; };
    [_empty setActionTitle:@"Mở Cài đặt"];
    [self.view addSubview:_empty];

    [NSLayoutConstraint activateConstraints:@[
        [_loading.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_loading.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_loading.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:20],
        [_loading.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-20],

        [_error.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_error.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_error.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [_error.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],

        [_empty.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_empty.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_empty.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [_empty.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
    ]];
}

- (void)buildAQICard
{
    ASGlassCard *card = [[ASGlassCard alloc] initWithEmphasis:YES];

    _ring = [[ASAQIRing alloc] initWithFrame:CGRectZero];
    _ring.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_ring];

    _headlineLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _headlineLabel.font = [ASDesign headlineFont];
    _headlineLabel.textColor = [ASDesign primaryText];
    _headlineLabel.textAlignment = NSTextAlignmentCenter;
    _headlineLabel.numberOfLines = 0;

    _aqiSourceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aqiSourceLabel.font = [ASDesign microFont];
    _aqiSourceLabel.textColor = [ASDesign tertiaryText];
    _aqiSourceLabel.textAlignment = NSTextAlignmentCenter;
    _aqiSourceLabel.numberOfLines = 0;

    _updatedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _updatedLabel.font = [ASDesign captionFont];
    _updatedLabel.textColor = [ASDesign tertiaryText];
    _updatedLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:@[_headlineLabel, _aqiSourceLabel, _updatedLabel]];
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = 6;
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:inner];

    UIButton *detail = [ASGlassButton primaryButtonWithTitle:@"Phân tích chất lượng không khí"
                                                      symbol:@"sparkles"];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    [detail addTarget:self action:@selector(openAirQualityDetail) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:detail];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [_ring.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset + 4],
        [_ring.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [_ring.widthAnchor constraintEqualToConstant:196],
        [_ring.heightAnchor constraintEqualToConstant:196],

        [inner.topAnchor constraintEqualToAnchor:_ring.bottomAnchor constant:14],
        [inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],

        [detail.topAnchor constraintEqualToAnchor:inner.bottomAnchor constant:14],
        [detail.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [detail.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [detail.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
    ]];

    [_content addArrangedSubview:card];
}

- (void)buildAlertCard
{
    _alertCard = [[ASGlassCard alloc] initWithEmphasis:NO];
    _alertCard.hidden = YES;
    _alertStack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _alertStack.axis = UILayoutConstraintAxisVertical;
    _alertStack.spacing = 8;
    _alertStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_alertCard addSubview:_alertStack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [_alertStack.topAnchor constraintEqualToAnchor:_alertCard.topAnchor constant:inset],
        [_alertStack.bottomAnchor constraintEqualToAnchor:_alertCard.bottomAnchor constant:-inset],
        [_alertStack.leadingAnchor constraintEqualToAnchor:_alertCard.leadingAnchor constant:inset],
        [_alertStack.trailingAnchor constraintEqualToAnchor:_alertCard.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_alertCard];
}

- (void)buildMetricSection
{
    UIView *header = [self sectionHeaderWithTitle:@"Chỉ số cảm biến"
                                           symbol:@"sensor.tag.radiowaves.forward"
                                            action:@selector(openAirQualityDetail)];
    [_content addArrangedSubview:header];

    _metricCards = [NSMutableArray array];
    _metricGrid = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _metricGrid.axis = UILayoutConstraintAxisVertical;
    _metricGrid.spacing = [ASDesign stackSpacing];
    [_content addArrangedSubview:_metricGrid];
}

- (void)buildDeviceCard
{
    UIView *header = [self sectionHeaderWithTitle:@"Thiết bị"
                                           symbol:@"cpu"
                                            action:@selector(openDeviceDetail)];
    [_content addArrangedSubview:header];

    _deviceCard = [[ASGlassCard alloc] initWithEmphasis:NO];
    _deviceValueLabels = [NSMutableArray array];
    _deviceRowLabels = [NSMutableArray array];

    UIStackView *rows = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    rows.axis = UILayoutConstraintAxisVertical;

    NSArray<NSArray<NSString *> *> *specs = @[
        @[@"Tên",        @"device.name",  @"iphone"],
        @[@"Địa chỉ",   @"addr",         @"network"],
        @[@"Wi-Fi",      @"wifi",         @"wifi"],
        @[@"Tín hiệu",  @"rssi",         @"antenna.radiowaves.left.and.right"],
        @[@"Uptime",     @"uptime",       @"clock.arrow.circlepath"],
        @[@"Firebase",   @"firebase",     @"flame"],
        @[@"Đèn",        @"led",          @"lightbulb"],
        @[@"Còi",        @"buzzer",       @"bell"],
        @[@"Quạt",       @"fan",          @"fanblades"],
        @[@"Cập nhật",  @"updated",      @"clock"],
    ];

    for (NSArray<NSString *> *spec in specs) {
        ASKeyValueRow *row = [[ASKeyValueRow alloc] initWithLabel:spec[0] value:@"--"];
        [row setSymbolName:spec[2]];
        [rows addArrangedSubview:row];
        [_deviceValueLabels addObject:row];
        [_deviceRowLabels addObject:spec[0]];
    }

    rows.translatesAutoresizingMaskIntoConstraints = NO;
    [_deviceCard addSubview:rows];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [rows.topAnchor constraintEqualToAnchor:_deviceCard.topAnchor constant:4],
        [rows.bottomAnchor constraintEqualToAnchor:_deviceCard.bottomAnchor constant:-4],
        [rows.leadingAnchor constraintEqualToAnchor:_deviceCard.leadingAnchor constant:inset],
        [rows.trailingAnchor constraintEqualToAnchor:_deviceCard.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_deviceCard];
}

#pragma mark - Layout

/// Rebuilds the metric grid for the current screen width. Called on rotation and on
/// first build so iPhone SE through Pro Max all get a sensible column count.
- (void)rebuildMetricGrid
{
    for (UIView *v in _metricGrid.arrangedSubviews) {
        [_metricGrid removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [_metricCards removeAllObjects];

    ASSnapshot *snap = [ASMonitor shared].snapshot;
    if (snap == nil) return;

    CGFloat inset = [ASDesign cardInset];
    CGFloat available = self.view.bounds.size.width - inset * 2;
    CGFloat minCell = 158.0;
    NSInteger columns = ASGridColumnCount(available, minCell, [ASDesign stackSpacing]);
    CGFloat spacing = [ASDesign stackSpacing];
    CGFloat cellWidth = (available - spacing * (columns - 1)) / columns;

    NSInteger count = (NSInteger)snap.readings.count;

    for (NSInteger rowIndex = 0; rowIndex * columns < count; rowIndex++) {
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = spacing;
        row.distribution = UIStackViewDistributionFillEqually;
        // Cards stretch to the tallest in the row.
        [row setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisVertical];

        for (NSInteger c = 0; c < columns; c++) {
            NSInteger index = rowIndex * columns + c;
            if (index >= count) {
                UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
                [row addArrangedSubview:spacer];
                continue;
            }
            ASMetricCard *card = [[ASMetricCard alloc] initWithReading:snap.readings[index]];
            [row addArrangedSubview:card];
            [_metricCards addObject:card];
        }
        [_metricGrid addArrangedSubview:row];
        (void)cellWidth;
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    _bgGradient.frame = self.view.bounds;
    // Rebuild only when the column count would actually change.
    CGFloat available = self.view.bounds.size.width - [ASDesign cardInset] * 2;
    NSInteger wanted = ASGridColumnCount(available, 158.0, [ASDesign stackSpacing]);
    if (wanted != _lastColumnCount) {
        _lastColumnCount = wanted;
        [self rebuildMetricGrid];
        [self monitorDidUpdate];
    }
}

#pragma mark - State

- (void)monitorDidUpdate
{
    ASMonitor *m = [ASMonitor shared];
    ASSnapshot *snap = m.snapshot;
    BOOL configured = [ASSettings shared].isConfigured;

    // Exactly one of: not-configured / first-load spinner / load error / content.
    BOOL notConfigured = !configured;
    BOOL noDataYet     = (snap == nil) && (m.lastError == nil);
    BOOL failed        = (snap == nil) && (m.lastError != nil);

    // The two states are mutually exclusive: a "configure first" empty state
    // never coexists with a network error, so we never get both buttons
    // ("Mở Cài đặt" and "Thử lại") drawn on top of each other.
    BOOL showEmpty = notConfigured && !failed;
    _empty.hidden   = !showEmpty;
    _loading.hidden = !(noDataYet || (m.loading && notConfigured));
    _error.hidden   = !failed;

    if (failed) {
        [_error applyMessage:ASFriendlyErrorMessage(m.lastError) retryTitle:@"Thử lại"];
    }
    if (notConfigured || snap == nil) { return; }

    [self applySnapshot:snap];
}

- (void)applySnapshot:(ASSnapshot *)snap
{
    ASMonitor *m = [ASMonitor shared];

    [_ring setValue:snap.aqi level:snap.aqiLevel animated:YES];
    _headlineLabel.text = ASAQIAdviceHeadline(snap.aqi, snap.aqiLevel);

    if (!isnan(snap.aqi)) {
        if (snap.aqiValue != nil) {
            _aqiSourceLabel.text = [NSString stringWithFormat:@"Chỉ số VN_AQI từ thiết bị%@ (QĐ 1459/QĐ-TCMT)",
                                    snap.aqiCategory.length > 0 ? [NSString stringWithFormat:@" · %@", snap.aqiCategory] : @""];
        } else {
            _aqiSourceLabel.text = @"AQI tính từ PM2.5";
        }
    } else {
        _aqiSourceLabel.text = @"AQI không có sẵn";
    }

    _updatedLabel.text = [NSString stringWithFormat:@"Cập nhật %@",
                          ASRelativeTimeString(snap.receivedAt)];

    [self updateMetricCardsWith:snap];
    [self updateAlertCardWith:snap];
    [self updateDeviceCardWith:snap];
    [self updateBanner];
    // Do NOT call applyBackground here: the gradient colors are dynamic
    // (colorWithDynamicProvider) and already follow overrideUserInterfaceStyle.
    // Re-applying them mid-refresh can trigger an unwanted redraw that makes
    // the background snap to the system-default (dark) style until layout settles.

    if (snap.alert.danger && !m.isStale) [ASDesign hapticWarning];
}

- (void)updateMetricCardsWith:(ASSnapshot *)snap
{
    // Rebuild when the reading set changes (first load, or a new device), otherwise patch in place.
    if (_metricCards.count != snap.readings.count) {
        [self rebuildMetricGrid];
        for (NSUInteger i = 0; i < _metricCards.count && i < snap.readings.count; i++) {
            [_metricCards[i] applyReading:snap.readings[i]];
        }
        return;
    }
    for (NSUInteger i = 0; i < _metricCards.count; i++) {
        [_metricCards[i] applyReading:snap.readings[i]];
    }
}

- (void)updateAlertCardWith:(ASSnapshot *)snap
{
    for (UIView *v in _alertStack.arrangedSubviews) {
        [_alertStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    ASReading *worst = snap.worst;
    if (!snap.alert.danger) {
        _alertCard.hidden = YES;
        _alertCard.layer.borderWidth = 0;
        return;
    }

    _alertCard.hidden = NO;
    _alertCard.layer.borderWidth = 1.5;
    _alertCard.layer.borderColor = [ASDesign dangerColor].CGColor;

    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    head.axis = UILayoutConstraintAxisHorizontal;
    head.spacing = 10;
    head.alignment = UIStackViewAlignmentCenter;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
    icon.tintColor = [ASDesign dangerColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                          weight:UIImageSymbolWeightSemibold];
    [icon.widthAnchor constraintEqualToConstant:22].active = YES;
    [icon.heightAnchor constraintEqualToConstant:22].active = YES;
    [head addArrangedSubview:icon];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"ĐANG CÓ CẢNH BÁO";
    title.font = [ASDesign headlineFont];
    title.textColor = [ASDesign dangerColor];
    [head addArrangedSubview:title];
    [_alertStack addArrangedSubview:head];

    NSArray<ASReading *> *tripped = snap.alert.tripped;
    if (tripped.count == 0) {
        // danger is set but no individual reading crosses a threshold — say so rather
        // than inventing a culprit.
        UILabel *body = [[UILabel alloc] initWithFrame:CGRectZero];
        body.text = @"Hệ thống ghi nhận trạng thái báo động nhưng các chỉ số đọc được vẫn trong giới hạn cho phép.";
        body.font = [ASDesign bodyFont];
        body.textColor = [ASDesign secondaryText];
        body.numberOfLines = 0;
        [_alertStack addArrangedSubview:body];
        return;
    }

    for (ASReading *r in tripped) {
        UILabel *line = [[UILabel alloc] initWithFrame:CGRectZero];
        line.font = [ASDesign bodyFont];
        line.textColor = [ASDesign primaryText];
        line.numberOfLines = 0;
        line.text = [NSString stringWithFormat:@"%@ đang ở %@ %@ — ngưỡng %@ %@",
                     r.label, ASTrimNumber(r.value.doubleValue), r.unit,
                     ASTrimNumber(r.threshold), r.unit];
        [_alertStack addArrangedSubview:line];
    }

    UILabel *act = [[UILabel alloc] initWithFrame:CGRectZero];
    act.font = [ASDesign captionFont];
    act.textColor = [ASDesign secondaryText];
    act.numberOfLines = 0;
    act.text = [NSString stringWithFormat:@"Chỉ số nguy hiểm nhất: %@ (%@%% ngưỡng).",
                worst.label ?: @"—", worst ? [@(round(worst.ratio * 100)) stringValue] : @"—"];
    [_alertStack addArrangedSubview:act];
}

- (void)updateDeviceCardWith:(ASSnapshot *)snap
{
    ASSettings *cfg = [ASSettings shared];

    NSMutableArray<NSString *> *values = [NSMutableArray array];
    [values addObject:cfg.deviceName.length ? cfg.deviceName : snap.device];
    // Don't leak dev URLs (ngrok) to users; show a friendly online/offline label.
    [values addObject:snap.wifiConnected ? @"Trực tuyến" : @"Ngoại tuyến"];
    [values addObject:snap.wifiConnected ? (snap.ssid.length ? snap.ssid : @"Đã kết nối") : @"Mất kết nối"];

    if (snap.rssi != nil) {
        NSInteger rssi = snap.rssi.integerValue;
        [values addObject:[NSString stringWithFormat:@"%ld dBm%@", (long)rssi, rssi >= -60 ? @" (tốt)" : (rssi >= -75 ? @" (khá)" : @" (yếu)")]];
    } else {
        [values addObject:@"—"];
    }

    [values addObject:ASUptimeString(snap.uptimeMs.doubleValue)];

    NSMutableString *fb = [NSMutableString string];
    [fb appendString:snap.firebase.enabled ? @"Đang bật" : @"Đang tắt"];
    if (snap.firebase.lastCode.integerValue != 0) {
        [fb appendFormat:@" · HTTP %ld", (long)snap.firebase.lastCode.integerValue];
    }
    if (snap.firebase.intervalMs.doubleValue > 0) {
        [fb appendFormat:@" · mỗi %.0fs", snap.firebase.intervalMs.doubleValue / 1000.0];
    }
    [values addObject:fb];

    [values addObject:snap.alert.led ? @"Đang bật" : @"Đang tắt"];
    [values addObject:snap.alert.buzzer ? @"Đang kêu" : @"Đang tắt"];
    [values addObject:snap.alert.fan ? @"Đang chạy" : @"Đang tắt"];
    [values addObject:ASRelativeTimeString(snap.receivedAt)];

    for (NSUInteger i = 0; i < _deviceValueLabels.count && i < values.count; i++) {
        ASKeyValueRow *row = (ASKeyValueRow *)_deviceValueLabels[i];
        BOOL warn = (i == 2 && !snap.wifiConnected);
        [row applyLabel:_deviceRowLabels[i] value:values[i]
          valueColor:warn ? [ASDesign dangerColor] : nil];
    }
}

- (void)updateBanner
{
    ASMonitor *m = [ASMonitor shared];
    if (m.snapshot == nil) { [_banner hide]; return; }

    if (m.reachability == ASReachabilityOffline) {
        [_banner applyText:[NSString stringWithFormat:@"Mất kết nối với ESP32. Đang hiển thị dữ liệu đã lưu %@.",
                           ASRelativeTimeString(m.snapshot.receivedAt)]
                    symbol:@"wifi.slash" color:[ASDesign dangerColor]];
    } else if (m.snapshotFromFirebase) {
        [_banner applyText:@"Không đọc được ESP32 trực tiếp — dữ liệu lấy từ Firebase esp32/latest."
                    symbol:@"icloud" color:[ASDesign warningColor]];
    } else if (m.isStale) {
        [_banner applyText:[NSString stringWithFormat:@"Dữ liệu có thể đã cũ — %@.",
                           ASRelativeTimeString(m.snapshot.receivedAt)]
                    symbol:@"clock.badge.exclamationmark" color:[ASDesign warningColor]];
    } else {
        [_banner hide];
    }
}

- (void)reachabilityDidChange
{
    [self monitorDidUpdate];
}

#pragma mark - Actions

- (void)pullToRefresh:(UIRefreshControl *)rc
{
    [[ASMonitor shared] refresh];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [rc endRefreshing];
    });
}

- (void)openAirQualityDetail
{
    [ASDesign hapticLight];
    [self.navigationController pushViewController:[[ASAirQualityViewController alloc] init] animated:YES];
}

- (void)openSettings
{
    [self.navigationController pushViewController:[[ASSettingsViewController alloc] init] animated:YES];
}

- (void)openDeviceDetail
{
    ASSettings *cfg = [ASSettings shared];
    ASSnapshot *snap = [ASMonitor shared].snapshot;

    NSMutableString *msg = [NSMutableString string];
    [msg appendFormat:@"Tên: %@\n", cfg.deviceName.length ? cfg.deviceName : @"Chưa đặt"];
    [msg appendFormat:@"Địa chỉ IP: %@", snap ? snap.device : @"—"];

    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Thiết bị"
                         message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end