// ASHistoryViewController — 1h / 6h / 24h / 7d / 30d charts.
// The ESP32 exposes no history endpoint, so samples come from two real sources:
//   1. Firebase RTDB esp32/history (only when the firmware's Firebase sync is enabled)
//   2. samples recorded on this phone while the app polled GET /api/data
// The UI always states which one produced the chart, and how much of the window is covered.

#import "UI/ASHistoryViewController.h"
#import "Components/ASComponents.h"
#import "Design/ASDesign.h"
#import "Services/ASMonitor.h"
#import "Models/ASHistory.h"
#import "Utils/ASJSON.h"
#import "Services/ASAPIClient.h"
#import "Services/ASSettings.h"
#import "Components/ASChartView.h"

@implementation ASHistoryViewController {
    UIScrollView *_scroll;
    UIStackView *_content;
    ASSegmentedControl *_rangeControl;
    ASSegmentedControl *_fieldControl;
    ASStatusBanner *_banner;
    ASLoadingView *_loading;
    ASErrorStateView *_error;
    ASEmptyStateView *_empty;

    ASChartView *_chart;
    UILabel *_summaryLabel;
    UILabel *_sourceLabel;
    UIStackView *_statsStack;
    NSMutableArray<UIView *> *_statTiles;

    ASRange _range;
    NSString *_field;
    NSArray<ASSample *> *_samples;
    ASHistorySource _source;
    NSUInteger _truncated;
    BOOL _fetching;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Lịch sử";
    self.view.backgroundColor = [ASDesign ambientBottomForLevel:ASAQILevelUnknown];
    _range = ASRange6H;
    _field = @"aqi";
    _samples = @[];
    _statTiles = [NSMutableArray array];

    [self buildContent];
    [self load];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (_samples.count == 0) [self load];
}

#pragma mark - Fields

- (NSArray<NSString *> *)fieldTitles       { return @[@"AQI", @"PM2.5", @"PM10", @"CO₂", @"LPG", @"CO", @"Nhiệt độ", @"Độ ẩm"]; }
- (NSArray<NSString *> *)fieldShortTitles  { return @[@"AQI", @"PM2.5", @"PM10", @"CO₂", @"LPG", @"CO", @"Nhiệt", @"Độ ẩm"]; }
- (NSArray<NSString *> *)fieldKeys         { return @[@"aqi", @"pm2_5", @"pm10", @"co2", @"lpg", @"co", @"temp", @"humidity"]; }
- (NSArray<NSString *> *)fieldUnits   { return @[@"", @"µg/m³", @"µg/m³", @"ppm", @"ppm", @"ppm", @"°C", @"%"]; }

- (NSString *)unitForField:(NSString *)field
{
    NSArray<NSString *> *keys = [self fieldKeys];
    NSUInteger i = [keys indexOfObject:field];
    if (i == NSNotFound) return @"";
    return [self fieldUnits][i];
}

#pragma mark - Build

- (void)buildContent
{
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];

    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
    _scroll.refreshControl = rc;

    _content = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _content.axis = UILayoutConstraintAxisVertical;
    _content.spacing = [ASDesign stackSpacing];
    _content.translatesAutoresizingMaskIntoConstraints = NO;
    _content.layoutMarginsRelativeArrangement = YES;
    _content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, [ASDesign cardInset], 30, [ASDesign cardInset]);
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

    [self buildControls];
    [self buildChartCard];
    [self buildStatsCard];
    [self buildClearCard];

    _loading = [[ASLoadingView alloc] initWithMessage:@"Đang tải lịch sử…"];
    _loading.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loading];

    _error = [[ASErrorStateView alloc] initWithMessage:@"Không tải được lịch sử." retryTitle:@"Thử lại"];
    _error.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _error.retryHandler = ^{ [weakSelf load]; };
    [self.view addSubview:_error];

    _empty = [[ASEmptyStateView alloc] initWithSymbol:@"chart.xyaxis.line"
                                              title:@"Chưa có dữ liệu lịch sử"
                                            message:@"ESP32 không có endpoint lịch sử. Bật đồng bộ Firebase để đọc esp32/history, hoặc để ứng dụng ghi mẫu trong lúc theo dõi."];
    _empty.translatesAutoresizingMaskIntoConstraints = NO;
    _empty.actionHandler = ^{ [weakSelf load]; };
    [_empty setActionTitle:@"Tải lại"];
    [self.view addSubview:_empty];

    [NSLayoutConstraint activateConstraints:@[
        [_loading.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_loading.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
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

- (UILabel *)sectionLabel:(NSString *)text
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = [ASDesign microFont];
    l.textColor = [ASDesign tertiaryText];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}

- (void)buildControls
{
    _rangeControl = [[ASSegmentedControl alloc] initWithFrame:CGRectZero];
    [_rangeControl setTitles:@[@"1g", @"6g", @"24g", @"7n", @"30n"] selectedIndex:1];
    _rangeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_rangeControl addTarget:self action:@selector(rangeChanged:) forControlEvents:UIControlEventValueChanged];

    _fieldControl = [[ASSegmentedControl alloc] initWithFrame:CGRectZero];
    [_fieldControl setTitles:[self fieldShortTitles] selectedIndex:0];
    _fieldControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_fieldControl addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *fields = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self sectionLabel:@"CHỈ SỐ"], _fieldControl]];
    fields.axis = UILayoutConstraintAxisVertical;
    fields.spacing = 6;

    UIStackView *ranges = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self sectionLabel:@"KHOẢNG THỜI GIAN"], _rangeControl]];
    ranges.axis = UILayoutConstraintAxisVertical;
    ranges.spacing = 6;

    [_content addArrangedSubview:fields];
    [_content addArrangedSubview:ranges];

    [NSLayoutConstraint activateConstraints:@[
        [_fieldControl.heightAnchor constraintEqualToConstant:36],
        [_rangeControl.heightAnchor constraintEqualToConstant:36],
    ]];
}

- (void)buildChartCard
{
    ASGlassCard *card = [[ASGlassCard alloc] initWithEmphasis:NO];

    _summaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _summaryLabel.font = [ASDesign headlineFont];
    _summaryLabel.textColor = [ASDesign primaryText];
    _summaryLabel.numberOfLines = 0;
    _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_summaryLabel];

    _sourceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _sourceLabel.font = [ASDesign microFont];
    _sourceLabel.textColor = [ASDesign tertiaryText];
    _sourceLabel.numberOfLines = 0;
    _sourceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_sourceLabel];

    _chart = [[ASChartView alloc] initWithFrame:CGRectZero];
    _chart.translatesAutoresizingMaskIntoConstraints = NO;
    _chart.showsFocusPoint = YES;
    __weak typeof(self) weakSelf = self;
    _chart.axisFormatter = ^NSString *(NSDate *date, ASRange range) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return @"";
        switch (range) {
            case ASRange1H: case ASRange6H: case ASRange24H: return ASShortTimeString(date);
            default: return ASShortDayString(date);
        }
    };
    [card addSubview:_chart];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [_summaryLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [_summaryLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [_summaryLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [_sourceLabel.topAnchor constraintEqualToAnchor:_summaryLabel.bottomAnchor constant:4],
        [_sourceLabel.leadingAnchor constraintEqualToAnchor:_summaryLabel.leadingAnchor],
        [_sourceLabel.trailingAnchor constraintEqualToAnchor:_summaryLabel.trailingAnchor],
        [_chart.topAnchor constraintEqualToAnchor:_sourceLabel.bottomAnchor constant:14],
        [_chart.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [_chart.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [_chart.heightAnchor constraintEqualToConstant:180],
        [_chart.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:card];
}

- (void)buildStatsCard
{
    ASGlassCard *card = [[ASGlassCard alloc] initWithEmphasis:NO];
    _statsStack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _statsStack.axis = UILayoutConstraintAxisHorizontal;
    _statsStack.distribution = UIStackViewDistributionFillEqually;
    _statsStack.spacing = 10;
    _statsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_statsStack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [_statsStack.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [_statsStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
        [_statsStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [_statsStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:card];
}

- (UILabel *)makeStatValue
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = [ASDesign headlineFont];
    l.textColor = [ASDesign primaryText];
    l.textAlignment = NSTextAlignmentCenter;
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.6;
    return l;
}

- (UILabel *)makeStatCaption:(NSString *)text
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = [ASDesign microFont];
    l.textColor = [ASDesign tertiaryText];
    l.textAlignment = NSTextAlignmentCenter;
    l.text = text;
    return l;
}

- (void)buildClearCard
{
    ASGlassCard *card = [[ASGlassCard alloc] initWithEmphasis:NO];

    UILabel *text = [[UILabel alloc] initWithFrame:CGRectZero];
    text.font = [ASDesign captionFont];
    text.textColor = [ASDesign secondaryText];
    text.numberOfLines = 0;
    text.text = @"Nhật ký mẫu ghi trên máy này (Documents/samples.jsonl). Xoá không ảnh hưởng dữ liệu Firebase.";
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:text];

    UIButton *clear = [ASGlassButton dangerButtonWithTitle:@"Xoá nhật ký cục bộ" symbol:@"trash"];
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [clear addTarget:self action:@selector(confirmClearLog) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:clear];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [text.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [text.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [text.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [clear.topAnchor constraintEqualToAnchor:text.bottomAnchor constant:12],
        [clear.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [clear.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [clear.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:card];
}

#pragma mark - Data

- (void)rangeChanged:(ASSegmentedControl *)sender
{
    _range = (ASRange)sender.selectedIndex;
    [self load];
}

- (void)fieldChanged:(ASSegmentedControl *)sender
{
    NSArray<NSString *> *keys = [self fieldKeys];
    NSUInteger i = (NSUInteger)MAX(0, MIN(sender.selectedIndex, (NSInteger)keys.count - 1));
    _field = keys[i];
    [self renderChartAnimated:YES];
}

- (void)pullToRefresh:(UIRefreshControl *)rc
{
    [self load];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [rc endRefreshing];
    });
}

- (void)load
{
    if (_fetching) return;
    _fetching = YES;
    _loading.hidden = NO;
    _error.hidden = YES;

    ASMonitor *m = [ASMonitor shared];
    ASSettings *cfg = [ASSettings shared];
    [cfg applyToClient:m.client];

    // Local log is always available and costs nothing.
    NSArray<ASSample *> *local = [m.historyStore samplesInRange:_range];

    // Firebase is only worth hitting when it is configured AND the device is syncing.
    BOOL canUseFirebase = cfg.firebaseConfigured && m.snapshot.firebase.enabled;
    if (!canUseFirebase) {
        _fetching = NO;
        _loading.hidden = YES;
        _samples = local;
        _source = ASHistorySourceDevice;
        _truncated = 0;
        if (local.count == 0 && m.snapshot == nil) {
            [_empty setActionTitle:@"Tải lại"];
        }
        [self renderChartAnimated:NO];
        [self updateBanner];
        return;
    }

    double intervalSec = m.snapshot.firebase.intervalMs.doubleValue / 1000.0;
    __weak typeof(self) weakSelf = self;
    [m.client fetchFirebaseHistoryForRange:_range espIntervalSeconds:intervalSec
                               completion:^(NSArray<ASSample *> *samples, NSUInteger truncated, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        strongSelf->_fetching = NO;
        strongSelf->_loading.hidden = YES;

        if (err) {
            // Fall back to the local log rather than showing nothing.
            strongSelf->_samples = local;
            strongSelf->_source = local.count ? ASHistorySourceDevice : ASHistorySourceNone;
            strongSelf->_truncated = 0;
            [_error applyMessage:ASFriendlyErrorMessage(err) retryTitle:@"Thử lại"];
            strongSelf->_error.hidden = (local.count > 0);
            if (local.count > 0) {
                [strongSelf->_banner applyText:@"Không đọc được Firebase — đang hiển thị nhật ký ghi trên máy."
                                       symbol:@"icloud.slash" color:[ASDesign warningColor]];
            }
        } else {
            strongSelf->_error.hidden = YES;
            strongSelf->_truncated = truncated;
            if (samples.count >= local.count) {
                strongSelf->_samples = samples;
                strongSelf->_source = ASHistorySourceFirebase;
            } else {
                strongSelf->_samples = local;
                strongSelf->_source = ASHistorySourceDevice;
            }
        }
        [strongSelf renderChartAnimated:YES];
        [strongSelf updateBanner];
    }];
}

#pragma mark - Render

- (void)renderChartAnimated:(BOOL)animated
{
    ASSeries *series = [self seriesForField:_field];
    _chart.range = _range;
    [_chart setSeries:series animated:animated];

    BOOL hasData = series.points.count > 0;
    _empty.hidden = hasData;
    _chart.hidden = !hasData;
    _summaryLabel.hidden = !hasData;
    _sourceLabel.hidden = !hasData;

    if (!hasData) {
        _summaryLabel.text = nil;
        _sourceLabel.text = nil;
    } else {
        NSString *name = [self fieldTitles][[[self fieldKeys] indexOfObject:_field]];
        NSString *unit = [self unitForField:_field];
        NSString *dir = series.trendRising ? @"▲ tăng" : (series.trendFalling ? @"▼ giảm" : @"→ đi ngang");
        NSString *deltaText = @"";
        if (series.points.count > 1 && !isnan(series.delta)) {
            NSString *sign = series.delta >= 0 ? @"+" : @"";
            deltaText = [NSString stringWithFormat:@" (%@%@)", sign, ASTrimNumber(series.delta)];
        }
        _summaryLabel.text = [NSString stringWithFormat:@"%@ · %@ %@ %@%@",
                              name, dir, ASTrimNumber(series.latest), unit, deltaText];

        _sourceLabel.text = [self provenanceTextForSeries:series];
    }

    [self renderStats:series];
}

- (NSString *)provenanceTextForSeries:(ASSeries *)series
{
    NSMutableString *s = [NSMutableString string];
    switch (_source) {
        case ASHistorySourceFirebase:
            [s appendString:@"Nguồn: Firebase esp32/history (REST, auth bằng secret đã lưu)"];
            break;
        case ASHistorySourceDevice:
            [s appendString:@"Nguồn: nhật ký ghi trên máy khi ứng dụng làm mới dữ liệu"];
            break;
        case ASHistorySourceNone:
            [s appendFormat:@"Chưa có nguồn nào trong %@", ASRangeName(_range)];
            break;
    }
    if (_truncated > 0) {
        [s appendFormat:@"\nCửa sổ đã bị giới hạn: %lu mẫu cũ hơn không được tải về.",
         (unsigned long)_truncated];
    }
    if (series.points.count < 2) {
        [s appendString:@"\nCần ít nhất hai mẫu để có xu hướng."];
    }
    return s;
}

- (void)renderStats:(ASSeries *)series
{
    for (UIView *v in _statTiles) { [_statsStack removeArrangedSubview:v]; [v removeFromSuperview]; }
    [_statTiles removeAllObjects];

    NSArray<NSString *> *values = @[
        series.avg ? ASTrimNumber(series.avg.doubleValue) : @"—",
        series.min ? ASTrimNumber(series.min.doubleValue) : @"—",
        series.max ? ASTrimNumber(series.max.doubleValue) : @"—",
    ];
    NSArray<NSString *> *captions = @[@"Trung bình", @"Thấp nhất", @"Cao nhất"];

    for (NSUInteger i = 0; i < values.count; i++) {
        UILabel *valueLabel = [self makeStatValue];
        valueLabel.text = values[i];
        UILabel *captionLabel = [self makeStatCaption:captions[i]];

        UIStackView *tile = [[UIStackView alloc] initWithArrangedSubviews:@[valueLabel, captionLabel]];
        tile.axis = UILayoutConstraintAxisVertical;
        tile.spacing = 2;
        [_statsStack addArrangedSubview:tile];
        [_statTiles addObject:tile];
    }
}

- (ASSeries *)seriesForField:(NSString *)field
{
    ASHistorySource source = _source;
    if ([field isEqualToString:@"aqi"]) {
        return ASBuildAQISeries(_samples, _range, source);
    }
    NSString *name = [self fieldTitles][[[self fieldKeys] indexOfObject:field]];
    return ASBuildSeries(_samples, field, name, [self unitForField:field], _range, source);
}

- (void)updateBanner
{
    ASMonitor *m = [ASMonitor shared];
    ASSettings *cfg = [ASSettings shared];

    if (_error.hidden == NO) { [_banner hide]; return; }

    if (!cfg.firebaseConfigured) {
        [_banner applyText:@"Chưa cấu hình Firebase. Lịch sử chỉ có những mẫu ứng dụng ghi khi bạn mở app."
                    symbol:@"key.slash" color:[ASDesign warningColor]];
    } else if (!m.snapshot.firebase.enabled) {
        [_banner applyText:@"Firebase trên ESP32 đang tắt, nên không có dữ liệu trong esp32/history. Bật ở Cài đặt."
                    symbol:@"icloud.slash" color:[ASDesign warningColor]];
    } else {
        [_banner hide];
    }
}

#pragma mark - Actions

- (void)confirmClearLog
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Xoá nhật ký cục bộ?"
                         message:[NSString stringWithFormat:@"%lu mẫu đã ghi trên máy sẽ bị xoá. Dữ liệu Firebase không bị ảnh hưởng.",
                                  (unsigned long)[ASMonitor shared].historyStore.totalSampleCount]
                 preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Xoá" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[ASMonitor shared].historyStore clear];
        [ASDesign hapticSuccess];
        [self load];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end