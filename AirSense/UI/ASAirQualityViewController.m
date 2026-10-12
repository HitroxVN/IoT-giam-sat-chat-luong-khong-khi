// ASAirQualityViewController — Full air-quality analysis for the current snapshot.
// Shows the AQI verdict, the pollutant breakdown, the dominant hazard, the AQI trend
// and the recommendation derived from the live AQI.

#import "UI/ASAirQualityViewController.h"
#import "Components/ASComponents.h"
#import "Design/ASDesign.h"
#import "Services/ASMonitor.h"
#import "Models/ASHistory.h"
#import "Utils/ASJSON.h"
#import "Services/ASAPIClient.h"
#import "Components/ASChartView.h"
#import "UI/ASGasDetailViewController.h"

@implementation ASAirQualityViewController {
    UIScrollView *_scroll;
    UIStackView *_content;
    ASStatusBanner *_banner;
    ASEmptyStateView *_empty;

    ASGlassCard *_verdictCard;
    ASAQIRing *_ring;
    UILabel *_headline;
    UILabel *_body;

    ASGlassCard *_pollutantCard;
    UIStackView *_pollutantStack;

    ASGlassCard *_worstCard;
    UILabel *_worstLabel;
    UILabel *_worstBody;

    ASGlassCard *_trendCard;
    ASChartView *_chart;
    UILabel *_trendSummary;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Chất lượng không khí";

    // Drill-down from Dashboard: show a back chevron to pop to the tab.
    self.navigationItem.hidesBackButton = NO;
    self.navigationController.navigationBarHidden = NO;
    self.view.backgroundColor = [ASDesign ambientBottomForLevel:ASAQILevelUnknown];

    [self buildContent];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(monitorDidUpdate)
                                                 name:ASMonitorDidUpdateNotification
                                               object:nil];
    [self monitorDidUpdate];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    BOOL isPushed = (self.navigationController.viewControllers.count > 1);
    [self.navigationController setNavigationBarHidden:!isPushed animated:animated];
    [self monitorDidUpdate];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    }
}

#pragma mark - Build

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines alignment:(NSTextAlignment)align
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.numberOfLines = lines;
    l.textAlignment = align;
    return l;
}

- (void)buildContent
{
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.alwaysBounceVertical = YES;
    _scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scroll];

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

    [self buildVerdictCard];
    [self buildPollutantCard];
    [self buildWorstCard];
    [self buildTrendCard];

    _empty = [[ASEmptyStateView alloc] initWithSymbol:@"wind"
                                               title:@"Chưa có dữ liệu"
                                             message:@"Kéo để làm mới sau khi ESP32 kết nối."];
    _empty.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_empty];
    [NSLayoutConstraint activateConstraints:@[
        [_empty.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_empty.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_empty.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [_empty.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
    ]];
}

- (void)buildVerdictCard
{
    _verdictCard = [[ASGlassCard alloc] initWithEmphasis:YES];

    _ring = [[ASAQIRing alloc] initWithFrame:CGRectZero];
    _ring.translatesAutoresizingMaskIntoConstraints = NO;
    [_verdictCard addSubview:_ring];

    _headline = [self labelWithFont:[ASDesign headlineFont] color:[ASDesign primaryText]
                              lines:2 alignment:NSTextAlignmentCenter];
    _headline.translatesAutoresizingMaskIntoConstraints = NO;
    [_verdictCard addSubview:_headline];

    _body = [self labelWithFont:[ASDesign bodyFont] color:[ASDesign secondaryText]
                          lines:0 alignment:NSTextAlignmentCenter];
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    [_verdictCard addSubview:_body];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [_ring.topAnchor constraintEqualToAnchor:_verdictCard.topAnchor constant:inset + 4],
        [_ring.centerXAnchor constraintEqualToAnchor:_verdictCard.centerXAnchor],
        [_ring.widthAnchor constraintEqualToConstant:196],
        [_ring.heightAnchor constraintEqualToConstant:196],

        [_headline.topAnchor constraintEqualToAnchor:_ring.bottomAnchor constant:14],
        [_headline.leadingAnchor constraintEqualToAnchor:_verdictCard.leadingAnchor constant:inset],
        [_headline.trailingAnchor constraintEqualToAnchor:_verdictCard.trailingAnchor constant:-inset],

        [_body.topAnchor constraintEqualToAnchor:_headline.bottomAnchor constant:8],
        [_body.leadingAnchor constraintEqualToAnchor:_verdictCard.leadingAnchor constant:inset],
        [_body.trailingAnchor constraintEqualToAnchor:_verdictCard.trailingAnchor constant:-inset],
        [_body.bottomAnchor constraintEqualToAnchor:_verdictCard.bottomAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_verdictCard];
}

- (void)buildPollutantCard
{
    _pollutantCard = [[ASGlassCard alloc] initWithEmphasis:NO];

    UILabel *title = [self labelWithFont:[ASDesign headlineFont] color:[ASDesign primaryText] lines:1 alignment:NSTextAlignmentLeft];
    title.text = @"Chỉ số gây ảnh hưởng";
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.85;
    [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIButton *gasBtn = [ASGlassButton secondaryButtonWithTitle:@"Cảm biến MQ" symbol:@"chevron.right"];
    gasBtn.configuration.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
    gasBtn.titleLabel.font = [ASDesign captionFont];
    [gasBtn setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [gasBtn setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [gasBtn addTarget:self action:@selector(openGasDetail) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[title, gasBtn]];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.alignment = UIStackViewAlignmentCenter;
    headerRow.spacing = 8;
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_pollutantCard addSubview:headerRow];

    _pollutantStack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _pollutantStack.axis = UILayoutConstraintAxisVertical;
    _pollutantStack.spacing = 0;
    _pollutantStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_pollutantCard addSubview:_pollutantStack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [headerRow.topAnchor constraintEqualToAnchor:_pollutantCard.topAnchor constant:inset],
        [headerRow.leadingAnchor constraintEqualToAnchor:_pollutantCard.leadingAnchor constant:inset],
        [headerRow.trailingAnchor constraintEqualToAnchor:_pollutantCard.trailingAnchor constant:-inset],

        [_pollutantStack.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:12],
        [_pollutantStack.bottomAnchor constraintEqualToAnchor:_pollutantCard.bottomAnchor constant:-inset],
        [_pollutantStack.leadingAnchor constraintEqualToAnchor:_pollutantCard.leadingAnchor constant:inset],
        [_pollutantStack.trailingAnchor constraintEqualToAnchor:_pollutantCard.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_pollutantCard];
}

- (void)buildWorstCard
{
    _worstCard = [[ASGlassCard alloc] initWithEmphasis:NO];

    _worstLabel = [self labelWithFont:[ASDesign headlineFont] color:[ASDesign primaryText] lines:2 alignment:NSTextAlignmentLeft];
    _worstLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_worstCard addSubview:_worstLabel];

    _worstBody = [self labelWithFont:[ASDesign bodyFont] color:[ASDesign secondaryText] lines:0 alignment:NSTextAlignmentLeft];
    _worstBody.translatesAutoresizingMaskIntoConstraints = NO;
    [_worstCard addSubview:_worstBody];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [_worstLabel.topAnchor constraintEqualToAnchor:_worstCard.topAnchor constant:inset],
        [_worstLabel.leadingAnchor constraintEqualToAnchor:_worstCard.leadingAnchor constant:inset],
        [_worstLabel.trailingAnchor constraintEqualToAnchor:_worstCard.trailingAnchor constant:-inset],
        [_worstBody.topAnchor constraintEqualToAnchor:_worstLabel.bottomAnchor constant:6],
        [_worstBody.leadingAnchor constraintEqualToAnchor:_worstCard.leadingAnchor constant:inset],
        [_worstBody.trailingAnchor constraintEqualToAnchor:_worstCard.trailingAnchor constant:-inset],
        [_worstBody.bottomAnchor constraintEqualToAnchor:_worstCard.bottomAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_worstCard];
}

- (void)buildTrendCard
{
    _trendCard = [[ASGlassCard alloc] initWithEmphasis:NO];

    UILabel *title = [self labelWithFont:[ASDesign headlineFont] color:[ASDesign primaryText] lines:1 alignment:NSTextAlignmentLeft];
    title.text = @"Xu hướng 24 giờ";
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [_trendCard addSubview:title];

    _trendSummary = [self labelWithFont:[ASDesign captionFont] color:[ASDesign secondaryText] lines:0 alignment:NSTextAlignmentLeft];
    _trendSummary.translatesAutoresizingMaskIntoConstraints = NO;
    [_trendCard addSubview:_trendSummary];

    _chart = [[ASChartView alloc] initWithFrame:CGRectZero];
    _chart.translatesAutoresizingMaskIntoConstraints = NO;
    _chart.showsFocusPoint = YES;
    [_trendCard addSubview:_chart];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:_trendCard.topAnchor constant:inset],
        [title.leadingAnchor constraintEqualToAnchor:_trendCard.leadingAnchor constant:inset],
        [title.trailingAnchor constraintEqualToAnchor:_trendCard.trailingAnchor constant:-inset],
        [_trendSummary.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [_trendSummary.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_trendSummary.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [_chart.topAnchor constraintEqualToAnchor:_trendSummary.bottomAnchor constant:12],
        [_chart.leadingAnchor constraintEqualToAnchor:_trendCard.leadingAnchor constant:inset],
        [_chart.trailingAnchor constraintEqualToAnchor:_trendCard.trailingAnchor constant:-inset],
        [_chart.heightAnchor constraintEqualToConstant:170],
        [_chart.bottomAnchor constraintEqualToAnchor:_trendCard.bottomAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_trendCard];
}

#pragma mark - State

- (void)monitorDidUpdate
{
    ASSnapshot *snap = [ASMonitor shared].snapshot;
    _empty.hidden = (snap != nil);
    if (snap == nil) return;

    double aqi = snap.aqi;
    [_ring setValue:aqi level:snap.aqiLevel animated:YES];
    _headline.text = ASAQIAdviceHeadline(aqi, snap.aqiLevel);
    _headline.textColor = [ASDesign colorForLevel:snap.aqiLevel];
    _body.text = ASAQIAdviceBody(aqi, snap.aqiLevel);

    [self rebuildPollutants:snap];
    [self updateWorst:snap];
    [self updateTrend];
    [self updateBanner];
}

- (void)rebuildPollutants:(ASSnapshot *)snap
{
    for (UIView *v in _pollutantStack.arrangedSubviews) {
        [_pollutantStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    for (ASReading *r in snap.readings) {
        ASKeyValueRow *row = [[ASKeyValueRow alloc] initWithLabel:r.label value:@"--"];
        [row setSymbolName:r.symbol];

        NSString *value;
        UIColor *color = [ASDesign primaryText];
        if (r.hasValue) {
            value = [NSString stringWithFormat:@"%@ %@", ASTrimNumber(r.value.doubleValue), r.unit];
            if (r.alerts) {
                value = [value stringByAppendingFormat:@"  ⚠︎ ngưỡng %@", ASTrimNumber(r.threshold)];
                color = [ASDesign dangerColor];
            }
        } else {
            value = @"Lỗi cảm biến";
            color = [ASDesign tertiaryText];
        }
        [row applyLabel:r.label value:value valueColor:color];

        UIView *sep = [[UIView alloc] initWithFrame:CGRectZero];
        sep.backgroundColor = [ASDesign separator];
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        [sep.heightAnchor constraintEqualToConstant:0.5].active = YES;
        [_pollutantStack addArrangedSubview:row];
        [_pollutantStack addArrangedSubview:sep];
    }
    _pollutantStack.arrangedSubviews.lastObject.hidden = YES;
}

- (void)updateWorst:(ASSnapshot *)snap
{
    ASReading *worst = snap.worst;
    if (worst == nil) {
        _worstLabel.text = @"Chỉ số nguy hiểm nhất";
        _worstLabel.textColor = [ASDesign primaryText];
        _worstBody.text = @"Không chỉ số nào đang vượt ngưỡng cảnh báo của ESP32.";
        return;
    }
    _worstLabel.text = [NSString stringWithFormat:@"Chỉ số nguy hiểm nhất: %@",
                        worst.label];
    _worstLabel.textColor = [ASDesign dangerColor];
    _worstBody.text = [NSString stringWithFormat:
        @"%@ đang ở %@ %@, bằng %ld%% ngưỡng %@ %@ mà ESP32 dùng để kích hoạt cảnh báo.",
        worst.label, ASTrimNumber(worst.value.doubleValue), worst.unit,
        (long)lround(worst.ratio * 100), ASTrimNumber(worst.threshold), worst.unit];
}

- (void)updateTrend
{
    ASHistoryStore *store = [ASMonitor shared].historyStore;
    NSArray<ASSample *> *samples = [store samplesInRange:ASRange24H];
    ASSeries *series = ASBuildAQISeries(samples, ASRange24H, ASHistorySourceDevice);
    _chart.range = ASRange24H;
    [_chart setSeries:series animated:YES];

    if (series.points.count < 2) {
        _trendSummary.text = @"Cần ít nhất hai mẫu để vẽ xu hướng. Ứng dụng ghi mẫu mỗi lần làm mới dữ liệu.";
        return;
    }

    NSString *dir = series.trendRising ? @"đang tăng" : (series.trendFalling ? @"đang giảm" : @"đi ngang");
    _trendSummary.text = [NSString stringWithFormat:
        @"AQI %@ trong %lu mẫu ghi trên máy này · hiện tại %@ · TB %@ · thấp nhất %@ · cao nhất %@",
        dir, (unsigned long)series.points.count,
        ASTrimNumber(series.latest), ASTrimNumber(series.avg.doubleValue),
        ASTrimNumber(series.min.doubleValue), ASTrimNumber(series.max.doubleValue)];
}

- (void)updateBanner
{
    ASMonitor *m = [ASMonitor shared];
    if (m.snapshot == nil) { [_banner hide]; return; }
    if (m.reachability == ASReachabilityOffline) {
        [_banner applyText:@"Mất kết nối — số liệu dưới đây là ảnh chụp gần nhất."
                    symbol:@"wifi.slash" color:[ASDesign dangerColor]];
    } else if (m.snapshotFromFirebase) {
        [_banner applyText:@"Nguồn: Firebase esp32/latest (không đọc được ESP32 trực tiếp)."
                    symbol:@"icloud" color:[ASDesign warningColor]];
    } else {
        [_banner hide];
    }
}

- (void)openGasDetail
{
    [ASDesign hapticLight];
    [self.navigationController pushViewController:[[ASGasDetailViewController alloc] init] animated:YES];
}

@end