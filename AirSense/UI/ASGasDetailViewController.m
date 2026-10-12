// ASGasDetailViewController — GET /api/mq and GET /api/mq/{key}.
// Shows each MQ sensor's ppm, raw ADC, calibration constants and validity, with the
// firmware's own caveat about ppm accuracy surfaced rather than hidden.

#import "UI/ASGasDetailViewController.h"
#import "Components/ASComponents.h"
#import "Design/ASDesign.h"
#import "Services/ASMonitor.h"
#import "Services/ASAPIClient.h"
#import "Utils/ASJSON.h"

/// Explicit references into one card, so updating never has to search the view tree.
@interface ASGasCardRefs : NSObject
@property (nonatomic, strong) ASGlassCard *card;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *subtitle;
@property (nonatomic, strong) UIStackView *rows;
@property (nonatomic, strong) UIProgressView *gauge;
@property (nonatomic, strong) UIButton *refreshButton;
@end

@implementation ASGasCardRefs
@end

@implementation ASGasDetailViewController {
    UIScrollView *_scroll;
    UIStackView *_content;
    UIStackView *_sensorStack;
    ASStatusBanner *_banner;
    ASLoadingView *_loading;
    ASErrorStateView *_error;
    NSMutableArray<ASGasCardRefs *> *_sensorCards;
    UIButton *_calibrateButton;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Cảm biến MQ";

    // The custom tab bar hides the nav bar by default. For this drill-down we need
    // the back chevron so users can return to Alerts after inspecting a sensor.
    self.navigationItem.hidesBackButton = NO;
    self.navigationController.navigationBarHidden = NO;
    UIBarButtonItem *back = [[UIBarButtonItem alloc]
        initWithTitle:@"Quay lại" style:UIBarButtonItemStylePlain target:nil action:NULL];
    self.navigationItem.backBarButtonItem = back;
    self.view.backgroundColor = [ASDesign ambientBottomForLevel:ASAQILevelUnknown];
    _sensorCards = [NSMutableArray array];

    [self buildContent];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(monitorDidUpdate)
                                                 name:ASMonitorDidUpdateNotification
                                               object:nil];
    [self reload];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController && self.navigationController.viewControllers.count == 1) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    }
}

- (void)buildContent
{
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];

    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(reloadFromUser) forControlEvents:UIControlEventValueChanged];
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

    _sensorStack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _sensorStack.axis = UILayoutConstraintAxisVertical;
    _sensorStack.spacing = [ASDesign stackSpacing];
    _sensorStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_content addArrangedSubview:_sensorStack];

    _loading = [[ASLoadingView alloc] initWithMessage:@"Đang đọc /api/mq…"];
    _loading.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loading];

    _error = [[ASErrorStateView alloc] initWithMessage:@"Không đọc được cảm biến MQ." retryTitle:@"Thử lại"];
    _error.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _error.retryHandler = ^{ [weakSelf reload]; };
    [self.view addSubview:_error];

    [NSLayoutConstraint activateConstraints:@[
        [_loading.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_loading.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_error.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_error.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_error.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [_error.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
    ]];

    [self buildCalibrationCard];
    [self buildCaveatCard];
}

- (void)buildCalibrationCard
{
    ASGlassCard *card = [[ASGlassCard alloc] initWithEmphasis:NO];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.image = [UIImage systemImageNamed:@"gauge.with.dots.needle.bottom.50percent"];
    icon.tintColor = [ASDesign goodColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:icon];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"Hiệu chuẩn R0 (Không khí sạch)";
    title.font = [ASDesign headlineFont];
    title.textColor = [ASDesign primaryText];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectZero];
    desc.text = @"POST /api/calibrate — ESP32 đo lại R0 cho cả 3 cảm biến MQ trong điều kiện không khí sạch và cập nhật ngay vào bộ nhớ đang chạy mà không cần nạp lại code.\n\nLưu ý: Chỉ thực hiện khi cảm biến đã được làm nóng (warm-up) ít nhất 5-10 phút và đang ở ngoài trời hoặc phòng thoáng khí sạch.";
    desc.font = [ASDesign captionFont];
    desc.textColor = [ASDesign secondaryText];
    desc.numberOfLines = 0;
    desc.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:desc];

    _calibrateButton = [ASGlassButton primaryButtonWithTitle:@"Bắt đầu hiệu chuẩn R0" symbol:@"sparkles"];
    _calibrateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_calibrateButton addTarget:self action:@selector(calibrateTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:_calibrateButton];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [icon.widthAnchor constraintEqualToConstant:24],
        [icon.heightAnchor constraintEqualToConstant:24],

        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset - 2],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],

        [desc.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [desc.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [desc.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],

        [_calibrateButton.topAnchor constraintEqualToAnchor:desc.bottomAnchor constant:12],
        [_calibrateButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [_calibrateButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [_calibrateButton.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
    ]];

    [_content addArrangedSubview:card];
}

- (void)buildCaveatCard
{
    ASGlassCard *card = [[ASGlassCard alloc] initWithEmphasis:NO];

    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectZero];
    icon.text = @"⚠︎";
    icon.font = [ASDesign titleFont];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:icon];

    UILabel *text = [[UILabel alloc] initWithFrame:CGRectZero];
    text.font = [ASDesign captionFont];
    text.textColor = [ASDesign secondaryText];
    text.numberOfLines = 0;
    text.text = @"Giá trị ppm do firmware quy đổi từ ADC theo đường đặc tuyến datasheet, không phải ppm thật. Sai số có thể gấp đôi hoặc hơn. r0 có thể được đo và cập nhật trực tiếp qua nút hiệu chuẩn ở trên mà không cần nạp lại firmware.";
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:text];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [text.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [text.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [text.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
        [icon.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:card];
}

#pragma mark - Data

- (void)reloadFromUser
{
    [self reload];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_scroll.refreshControl endRefreshing];
    });
}

- (void)reload
{
    _loading.hidden = NO;
    _error.hidden = YES;
    [ASMonitor.shared refreshGasSensors];
    [self render];
}

- (void)monitorDidUpdate
{
    [self render];
}

- (void)render
{
    ASGasReading *reading = [ASMonitor shared].gasReading;

    BOOL hasData = (reading.sensors.count > 0);
    _loading.hidden = hasData;
    if (!hasData) {
        NSError *err = [ASMonitor shared].lastError;
        if (err) {
            [_error applyMessage:ASFriendlyErrorMessage(err) retryTitle:@"Thử lại"];
            _error.hidden = NO;
        }
    } else {
        _error.hidden = YES;
    }

    if (!hasData) return;

    if (_sensorCards.count != reading.sensors.count) {
        [self rebuildCardsForCount:reading.sensors.count];
    }
    for (NSUInteger i = 0; i < _sensorCards.count && i < reading.sensors.count; i++) {
        [self fillCard:_sensorCards[i] withSensor:reading.sensors[i]];
    }
}

- (void)rebuildCardsForCount:(NSUInteger)count
{
    for (ASGasCardRefs *refs in _sensorCards) {
        [_sensorStack removeArrangedSubview:refs.card];
        [refs.card removeFromSuperview];
    }
    [_sensorCards removeAllObjects];

    NSArray<NSString *> *symbols = @[@"aqi.low", @"flame", @"smoke"];
    for (NSUInteger i = 0; i < count; i++) {
        ASGasCardRefs *refs = [[ASGasCardRefs alloc] init];
        refs.card = [[ASGlassCard alloc] initWithEmphasis:NO];

        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.image = [UIImage systemImageNamed:i < symbols.count ? symbols[i] : @"aqi.medium"];
        icon.tintColor = [ASDesign secondaryText];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:22
                                                                                               weight:UIImageSymbolWeightSemibold];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [refs.card addSubview:icon];

        refs.title = [[UILabel alloc] initWithFrame:CGRectZero];
        refs.title.font = [ASDesign titleFont];
        refs.title.textColor = [ASDesign primaryText];
        refs.title.translatesAutoresizingMaskIntoConstraints = NO;
        [refs.card addSubview:refs.title];

        refs.subtitle = [[UILabel alloc] initWithFrame:CGRectZero];
        refs.subtitle.font = [ASDesign microFont];
        refs.subtitle.textColor = [ASDesign tertiaryText];
        refs.subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        [refs.card addSubview:refs.subtitle];

        refs.rows = [[UIStackView alloc] initWithArrangedSubviews:@[]];
        refs.rows.axis = UILayoutConstraintAxisVertical;
        refs.rows.translatesAutoresizingMaskIntoConstraints = NO;
        [refs.card addSubview:refs.rows];

        refs.gauge = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        refs.gauge.translatesAutoresizingMaskIntoConstraints = NO;
        refs.gauge.progressTintColor = [ASDesign secondaryText];
        refs.gauge.trackTintColor = [ASDesign separator];
        [refs.card addSubview:refs.gauge];

        // Per-sensor button exercises GET /api/mq/{key}.
        refs.refreshButton = [ASGlassButton secondaryButtonWithTitle:@"Đọc lại" symbol:@"arrow.clockwise"];
        refs.refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
        [refs.refreshButton addTarget:self action:@selector(refreshSingleSensor:)
                      forControlEvents:UIControlEventTouchUpInside];
        [refs.card addSubview:refs.refreshButton];

        CGFloat inset = [ASDesign cardPadding];
        [NSLayoutConstraint activateConstraints:@[
            [icon.topAnchor constraintEqualToAnchor:refs.card.topAnchor constant:inset],
            [icon.leadingAnchor constraintEqualToAnchor:refs.card.leadingAnchor constant:inset],
            [icon.widthAnchor constraintEqualToConstant:26],
            [icon.heightAnchor constraintEqualToConstant:26],

            [refs.title.topAnchor constraintEqualToAnchor:refs.card.topAnchor constant:inset - 3],
            [refs.title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
            [refs.title.trailingAnchor constraintLessThanOrEqualToAnchor:refs.card.trailingAnchor constant:-inset],

            [refs.subtitle.topAnchor constraintEqualToAnchor:refs.title.bottomAnchor constant:1],
            [refs.subtitle.leadingAnchor constraintEqualToAnchor:refs.title.leadingAnchor],
            [refs.subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:refs.card.trailingAnchor constant:-inset],

            [refs.rows.topAnchor constraintEqualToAnchor:refs.subtitle.bottomAnchor constant:8],
            [refs.rows.leadingAnchor constraintEqualToAnchor:refs.card.leadingAnchor constant:inset],
            [refs.rows.trailingAnchor constraintEqualToAnchor:refs.card.trailingAnchor constant:-inset],

            [refs.refreshButton.topAnchor constraintEqualToAnchor:refs.rows.bottomAnchor constant:12],
            [refs.refreshButton.leadingAnchor constraintEqualToAnchor:refs.card.leadingAnchor constant:inset],
            [refs.refreshButton.trailingAnchor constraintEqualToAnchor:refs.card.trailingAnchor constant:-inset],

            [refs.gauge.topAnchor constraintEqualToAnchor:refs.refreshButton.bottomAnchor constant:10],
            [refs.gauge.leadingAnchor constraintEqualToAnchor:refs.card.leadingAnchor constant:inset],
            [refs.gauge.trailingAnchor constraintEqualToAnchor:refs.card.trailingAnchor constant:-inset],
            [refs.gauge.heightAnchor constraintEqualToConstant:2],
            [refs.gauge.bottomAnchor constraintEqualToAnchor:refs.card.bottomAnchor constant:-10],
        ]];

        [_sensorStack addArrangedSubview:refs.card];
        [_sensorCards addObject:refs];
    }
}

/// The thresholds the firmware ships as defaults, per the MQ key.
static double ASDefaultThresholdForKey(NSString *key)
{
    if ([key isEqualToString:@"mq135"]) return 1500;   // CO2
    if ([key isEqualToString:@"mq2"])   return 400;    // LPG
    if ([key isEqualToString:@"mq7"])   return 50;     // CO
    return NAN;
}

- (void)fillCard:(ASGasCardRefs *)refs withSensor:(ASGasSensor *)sensor
{
    for (UIView *v in refs.rows.arrangedSubviews) {
        [refs.rows removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    double threshold = ASDefaultThresholdForKey(sensor.key);
    BOOL alerting = !sensor.negative && !isnan(threshold) && sensor.ppm.doubleValue >= threshold;

    refs.title.text = sensor.gas.length ? sensor.gas : sensor.key;
    refs.subtitle.text = sensor.key;

    NSString *ppmText;
    UIColor *ppmColor = [ASDesign primaryText];
    if (sensor.negative) {
        // API.md: a negative ppm means the read failed.
        ppmText = @"Lần đọc lỗi (ppm âm)";
        ppmColor = [ASDesign dangerColor];
    } else {
        ppmText = [NSString stringWithFormat:@"%@ ppm", ASPlainNumber(sensor.ppm.doubleValue)];
        if (alerting) {
            ppmText = [ppmText stringByAppendingFormat:@"  ⚠︎ ngưỡng %@", ASTrimNumber(threshold)];
            ppmColor = [ASDesign dangerColor];
        }
    }

    NSString *adcText = sensor.adc != nil
        ? [NSString stringWithFormat:@"%@ / 4095", ASPlainNumber(sensor.adc.doubleValue)]
        : @"—";

    NSArray<NSArray<NSString *> *> *rows = @[
        @[@"Nồng độ",  ppmText],
        @[@"ADC thô",  adcText],
        @[@"R0 sạch",  sensor.r0 ? ASPlainNumber(sensor.r0.doubleValue) : @"—"],
        @[@"Hệ số a",  sensor.a  ? ASPlainNumber(sensor.a.doubleValue)  : @"—"],
        @[@"Hệ số b",  sensor.b  ? ASPlainNumber(sensor.b.doubleValue)  : @"—"],
        @[@"valid",    sensor.valid ? @"true" : @"false"],
    ];

    for (NSUInteger i = 0; i < rows.count; i++) {
        BOOL isReading = (i == 0);
        ASKeyValueRow *row = [[ASKeyValueRow alloc] initWithLabel:rows[i][0] value:rows[i][1]];
        [row applyLabel:rows[i][0]
                  value:rows[i][1]
            valueColor:isReading ? ppmColor : [ASDesign secondaryText]];
        [refs.rows addArrangedSubview:row];
    }

    [refs.refreshButton setTitle:[NSString stringWithFormat:@"Đọc lại %@", sensor.key]
                        forState:UIControlStateNormal];
    refs.refreshButton.accessibilityIdentifier = sensor.key;

    refs.gauge.progress = (float)sensor.adcFraction;
    refs.gauge.progressTintColor = alerting ? [ASDesign dangerColor] : [ASDesign secondaryText];
    refs.card.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", refs.title.text, ppmText];
}

#pragma mark - GET /api/mq/{key}

- (void)refreshSingleSensor:(UIButton *)sender
{
    NSString *key = sender.accessibilityIdentifier;
    if (key.length == 0) return;
    [ASDesign hapticLight];
    [sender setTitle:@"Đang đọc…" forState:UIControlStateNormal];
    sender.enabled = NO;

    __weak typeof(self) weakSelf = self;
    [[ASMonitor shared].client fetchGasSensorForKey:key completion:^(ASGasSensor *sensor, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        sender.enabled = YES;
        [sender setTitle:[NSString stringWithFormat:@"Đọc lại %@", key] forState:UIControlStateNormal];

        if (err) {
            [ASDesign hapticError];
            [strongSelf->_banner applyText:ASFriendlyErrorMessage(err) symbol:@"exclamationmark.triangle" color:[ASDesign dangerColor]];
            return;
        }
        // Fold the single-sensor response back into the shared reading.
        ASGasReading *updated = [ASMonitor shared].gasReading;
        if (updated == nil) { return; }
        NSMutableArray<ASGasSensor *> *list = [updated.sensors mutableCopy];
        for (NSUInteger i = 0; i < list.count; i++) {
            if ([list[i].key isEqualToString:key]) { list[i] = sensor; break; }
        }
        updated.sensors = list;
        [ASDesign hapticSuccess];
        [strongSelf render];
    }];
}

#pragma mark - POST /api/calibrate

- (void)calibrateTapped:(UIButton *)sender
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hiệu chuẩn R0"
                                                                   message:@"Cần đảm bảo cảm biến đã được làm nóng (warm-up) tối thiểu 5-10 phút và đang ở môi trường ngoài trời hoặc phòng thoáng khí sạch.\n\nESP32 sẽ lấy 30 mẫu đọc trong không khí sạch để tính R0 mới."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Bắt đầu đo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf executeCalibration];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)executeCalibration
{
    _calibrateButton.enabled = NO;
    [_calibrateButton setTitle:@"Đang hiệu chuẩn…" forState:UIControlStateNormal];
    [ASDesign hapticLight];

    __weak typeof(self) weakSelf = self;
    [[ASMonitor shared] calibrateSensorsWithSamples:30 completion:^(NSDictionary *result, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        strongSelf->_calibrateButton.enabled = YES;
        [strongSelf->_calibrateButton setTitle:@"Bắt đầu hiệu chuẩn R0" forState:UIControlStateNormal];

        if (err) {
            [ASDesign hapticError];
            [strongSelf showAlertWithTitle:@"Hiệu chuẩn thất bại" message:ASFriendlyErrorMessage(err)];
            return;
        }

        [ASDesign hapticSuccess];
        NSDictionary *r0 = [result isKindOfClass:[NSDictionary class]] ? result[@"r0"] : nil;
        NSString *detail = @"";
        if ([r0 isKindOfClass:[NSDictionary class]]) {
            detail = [NSString stringWithFormat:@"\n\nGiá trị R0 mới:\n• MQ-135: %@\n• MQ-2: %@\n• MQ-7: %@",
                      ASTrimNumber([r0[@"mq135"] doubleValue]),
                      ASTrimNumber([r0[@"mq2"] doubleValue]),
                      ASTrimNumber([r0[@"mq7"] doubleValue])];
        }
        [strongSelf showAlertWithTitle:@"Hiệu chuẩn thành công"
                               message:[NSString stringWithFormat:@"Đã cập nhật giá trị R0 mới vào ESP32.%@", detail]];
        [strongSelf reload];
    }];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end