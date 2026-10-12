// ASAlertsViewController — Active conditions plus direct hardware control.
// Every row here is derived from live /api/data; the switches issue the POST commands
// documented in API.md and then re-read the device instead of assuming the change stuck.

#import "UI/ASAlertsViewController.h"
#import "Components/ASComponents.h"
#import "Design/ASDesign.h"
#import "Services/ASMonitor.h"
#import "Utils/ASJSON.h"
#import "Services/ASAPIClient.h"
#import "UI/ASGasDetailViewController.h"

/// Refs into a command card, returned rather than written through an out-parameter
/// (an ivar's address cannot be passed to an __strong out-param).
@interface ASCommandCard : NSObject
@property (nonatomic, strong) ASSegmentedControl *control;
@property (nonatomic, strong) UILabel *status;
@end

@implementation ASCommandCard
@end

@implementation ASAlertsViewController {
    UIScrollView *_scroll;
    UIStackView *_content;
    ASStatusBanner *_banner;
    ASEmptyStateView *_empty;
    ASErrorStateView *_error;

    ASGlassCard *_controlCard;
    UIStackView *_conditionStack;

    ASGlassCard *_ledCard;
    ASGlassCard *_buzzerCard;
    ASSegmentedControl *_ledControl;
    ASSegmentedControl *_buzzerControl;
    ASSegmentedControl *_fanControl;
    UILabel *_ledStatus;
    UILabel *_buzzerStatus;
    UILabel *_fanStatus;

    ASGlassCard *_thresholdCard;
    NSMutableDictionary<NSString *, UITextField *> *_thresholdFields;
    NSMutableArray<UIButton *> *_saveButtons;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Cảnh báo";
    self.view.backgroundColor = [ASDesign ambientBottomForLevel:ASAQILevelUnknown];
    _thresholdFields = [NSMutableDictionary dictionary];
    _saveButtons = [NSMutableArray array];

    [self buildContent];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(monitorDidUpdate)
                                                 name:ASMonitorDidUpdateNotification
                                               object:nil];
    [self monitorDidUpdate];
    [[ASMonitor shared] refreshGasSensors];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = font;
    l.textColor = color;
    l.numberOfLines = lines;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
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

    [self buildConditionCard];
    [self buildThresholdCard];
    [self buildLedCard];
    [self buildBuzzerCard];
    [self buildFanCard];

    _empty = [[ASEmptyStateView alloc] initWithSymbol:@"checkmark.shield"
                                              title:@"Không có cảnh báo"
                                            message:@"Mọi chỉ số đang dưới ngưỡng mà ESP32 dùng để kích hoạt cảnh báo."];
    _empty.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_empty];
    [NSLayoutConstraint activateConstraints:@[
        [_empty.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_empty.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_empty.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [_empty.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
    ]];

    _error = [[ASErrorStateView alloc] initWithMessage:@"Không đọc được trạng thái thiết bị." retryTitle:@"Thử lại"];
    _error.translatesAutoresizingMaskIntoConstraints = NO;
    _error.retryHandler = ^{ [[ASMonitor shared] refresh]; };
    [self.view addSubview:_error];
    [NSLayoutConstraint activateConstraints:@[
        [_error.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_error.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_error.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [_error.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
    ]];
}

- (void)buildConditionCard
{
    ASGlassCard *card = [[ASGlassCard alloc] initWithEmphasis:NO];
    UILabel *title = [self labelWithText:@"Điều kiện hiện tại" font:[ASDesign headlineFont]
                                   color:[ASDesign primaryText] lines:1];
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.85;
    [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIButton *gas = [ASGlassButton secondaryButtonWithTitle:@"MQ" symbol:@"list.bullet.rectangle"];
    gas.configuration.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
    gas.titleLabel.font = [ASDesign captionFont];
    [gas setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [gas setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [gas addTarget:self action:@selector(openGasDetail) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[title, gas]];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.alignment = UIStackViewAlignmentCenter;
    headerRow.spacing = 8;
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:headerRow];

    _conditionStack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _conditionStack.axis = UILayoutConstraintAxisVertical;
    _conditionStack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_conditionStack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [headerRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [headerRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [headerRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],

        [_conditionStack.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:12],
        [_conditionStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [_conditionStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [_conditionStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:card];
}

/// Builds one card with a title, a segmented control and a status line.
- (ASCommandCard *)buildCommandCardWithTitle:(NSString *)title
                            symbol:(NSString *)symbol
                           explain:(NSString *)explain
                            titles:(NSArray<NSString *> *)titles
                          selected:(NSInteger)selected
                          handler:(SEL)handler
{
    ASGlassCard *card = [[ASGlassCard alloc] initWithEmphasis:NO];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.image = [UIImage systemImageNamed:symbol];
    icon.tintColor = [ASDesign secondaryText];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:20
                                                                                           weight:UIImageSymbolWeightSemibold];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:icon];

    UILabel *t = [self labelWithText:title font:[ASDesign headlineFont] color:[ASDesign primaryText] lines:1];
    [card addSubview:t];

    UILabel *sub = [self labelWithText:explain font:[ASDesign microFont] color:[ASDesign tertiaryText] lines:0];
    [card addSubview:sub];

    ASSegmentedControl *seg = [[ASSegmentedControl alloc] initWithFrame:CGRectZero];
    [seg setTitles:titles selectedIndex:selected];
    seg.translatesAutoresizingMaskIntoConstraints = NO;
    [seg addTarget:self action:handler forControlEvents:UIControlEventValueChanged];
    [card addSubview:seg];

    UILabel *status = [self labelWithText:@"" font:[ASDesign captionFont] color:[ASDesign secondaryText] lines:0];
    status.textAlignment = NSTextAlignmentCenter;
    [card addSubview:status];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [icon.widthAnchor constraintEqualToConstant:24],
        [icon.heightAnchor constraintEqualToConstant:24],
        [t.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset - 2],
        [t.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [t.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [sub.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:2],
        [sub.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [sub.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [seg.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:12],
        [seg.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [seg.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [seg.heightAnchor constraintEqualToConstant:38],
        [status.topAnchor constraintEqualToAnchor:seg.bottomAnchor constant:10],
        [status.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [status.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [status.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
    ]];

    [_content addArrangedSubview:card];
    ASCommandCard *refs = [[ASCommandCard alloc] init];
    refs.control = seg;
    refs.status = status;
    return refs;
}

- (void)buildLedCard
{
    ASCommandCard *refs = [self buildCommandCardWithTitle:@"Đèn LED"
                                                   symbol:@"lightbulb.fill"
                                                  explain:@"Bật, tắt thủ công hoặc Tự động sáng khi phát hiện ô nhiễm vượt ngưỡng."
                                                   titles:@[@"Tắt", @"Bật", @"Tự động"]
                                                 selected:-1
                                                  handler:@selector(ledChanged:)];
    _ledControl = refs.control;
    _ledStatus = refs.status;
}

- (void)buildBuzzerCard
{
    ASCommandCard *refs = [self buildCommandCardWithTitle:@"Còi báo"
                                                   symbol:@"bell.fill"
                                                  explain:@"Bật, tắt thủ công hoặc Tự động hú còi khi mức cảnh báo nguy hiểm."
                                                   titles:@[@"Tắt", @"Bật", @"Tự động"]
                                                 selected:-1
                                                  handler:@selector(buzzerChanged:)];
    _buzzerControl = refs.control;
    _buzzerStatus = refs.status;
}

- (void)buildFanCard
{
    ASCommandCard *refs = [self buildCommandCardWithTitle:@"Quạt thông gió"
                                                   symbol:@"fanblades.fill"
                                                  explain:@"Bật, tắt thủ công hoặc Tự động kích hoạt khi mức cảnh báo nguy hiểm."
                                                   titles:@[@"Tắt", @"Bật", @"Tự động"]
                                                 selected:-1
                                                  handler:@selector(fanChanged:)];
    _fanControl = refs.control;
    _fanStatus = refs.status;
}

- (UITextField *)makeFieldWithPlaceholder:(NSString *)placeholder
{
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectZero];
    f.placeholder = placeholder;
    f.font = [ASDesign bodyFont];
    f.textColor = [ASDesign primaryText];
    f.backgroundColor = [[ASDesign primaryText] colorWithAlphaComponent:0.06];
    f.layer.cornerRadius = 12;
    f.layer.cornerCurve = kCACornerCurveContinuous;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.keyboardType = UIKeyboardTypeDecimalPad;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    f.leftView = pad;
    f.leftViewMode = UITextFieldViewModeAlways;
    [f.heightAnchor constraintEqualToConstant:40].active = YES;
    return f;
}

- (void)buildThresholdCard
{
    _thresholdCard = [[ASGlassCard alloc] initWithEmphasis:NO];

    UILabel *title = [self labelWithText:@"Ngưỡng kích hoạt cảnh báo"
                                    font:[ASDesign headlineFont]
                                   color:[ASDesign primaryText]
                                   lines:1];

    UILabel *note = [self labelWithText:@"Khi chỉ số vượt ngưỡng, ESP32 sẽ bật đèn, hú còi và chạy quạt thông gió (nếu đặt Tự động). Ghi đè bằng nút Ghi bên cạnh."
                                   font:[ASDesign captionFont]
                                  color:[ASDesign secondaryText]
                                  lines:0];

    UIStackView *rows = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 10;

    NSArray<NSArray<NSString *> *> *specs = @[
        @[@"pm2_5", @"PM2.5", @"µg/m³"],
        @[@"pm10",  @"PM10",  @"µg/m³"],
        @[@"co2",   @"CO₂",   @"ppm"],
        @[@"lpg",   @"LPG",   @"ppm"],
        @[@"co",    @"CO",    @"ppm"],
    ];

    for (NSArray<NSString *> *spec in specs) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = [NSString stringWithFormat:@"%@ (%@)", spec[1], spec[2]];
        label.font = [ASDesign bodyFont];
        label.textColor = [ASDesign secondaryText];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label.widthAnchor constraintEqualToConstant:120].active = YES;

        UITextField *field = [self makeFieldWithPlaceholder:@"—"];
        field.accessibilityIdentifier = spec[0];
        _thresholdFields[spec[0]] = field;

        UIButton *save = [ASGlassButton primaryButtonWithTitle:@"Ghi" symbol:@"arrow.up.circle"];
        save.accessibilityIdentifier = spec[0];
        save.translatesAutoresizingMaskIntoConstraints = NO;
        [save.widthAnchor constraintEqualToConstant:64].active = YES;
        [save addTarget:self action:@selector(saveThreshold:) forControlEvents:UIControlEventTouchUpInside];
        [_saveButtons addObject:save];

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, field, save]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 8;
        row.alignment = UIStackViewAlignmentCenter;
        [rows addArrangedSubview:row];
    }

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, note, rows]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_thresholdCard addSubview:stack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:_thresholdCard.topAnchor constant:inset],
        [stack.bottomAnchor constraintEqualToAnchor:_thresholdCard.bottomAnchor constant:-inset],
        [stack.leadingAnchor constraintEqualToAnchor:_thresholdCard.leadingAnchor constant:inset],
        [stack.trailingAnchor constraintEqualToAnchor:_thresholdCard.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_thresholdCard];
}

#pragma mark - State

- (void)monitorDidUpdate
{
    ASSnapshot *snap = [ASMonitor shared].snapshot;

    BOOL hasData = (snap != nil);
    _error.hidden = hasData || [ASMonitor shared].lastError == nil;
    if (!hasData && [ASMonitor shared].lastError) {
        [_error applyMessage:ASFriendlyErrorMessage([ASMonitor shared].lastError) retryTitle:@"Thử lại"];
    }
    _empty.hidden = hasData || !_error.hidden;
    if (!hasData) return;

    [self rebuildConditions:snap];
    [self updateHardwareStatus:snap];

    if ([ASMonitor shared].reachability == ASReachabilityOffline) {
        [_banner applyText:@"Mất kết nối — không thể gửi lệnh điều khiển." symbol:@"wifi.slash" color:[ASDesign dangerColor]];
    } else {
        [_banner hide];
    }
}

- (void)rebuildConditions:(ASSnapshot *)snap
{
    for (UIView *v in _conditionStack.arrangedSubviews) {
        [_conditionStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSString *levelText = @"An toàn";
    UIColor *levelColor = [ASDesign goodColor];
    if ([snap.alert.level isEqualToString:@"warning"]) {
        levelText = @"Cảnh báo";
        levelColor = [ASDesign warningColor];
    } else if ([snap.alert.level isEqualToString:@"danger"] || snap.alert.danger) {
        levelText = @"Nguy hiểm";
        levelColor = [ASDesign dangerColor];
    }

    NSArray<NSArray *> *rows = @[
        @[@"Trạng thái", snap.alert.danger ? @"ĐANG BÁO ĐỘNG" : @"Bình thường", snap.alert.danger ? [ASDesign dangerColor] : [ASDesign goodColor]],
        @[@"Mức độ",     levelText, levelColor],
    ];
    for (NSArray *row in rows) {
        ASKeyValueRow *kv = [[ASKeyValueRow alloc] initWithLabel:row[0] value:row[1]];
        [kv applyLabel:row[0] value:row[1] valueColor:row[2]];
        [_conditionStack addArrangedSubview:kv];
    }

    if (snap.alert.tripped.count == 0) {
        if (snap.alert.danger) {
            [self addNoteToStack:@"Hệ thống ghi nhận trạng thái báo động nhưng các chỉ số đọc được vẫn trong giới hạn cho phép — có thể cảm biến đang làm nóng hoặc gặp nhiễu tín hiệu."];
        }
    } else {
        for (ASReading *r in snap.alert.tripped) {
            ASKeyValueRow *kv = [[ASKeyValueRow alloc] initWithLabel:r.label value:@""];
            [kv setSymbolName:r.symbol];
            [kv applyLabel:r.label
                    value:[NSString stringWithFormat:@"%@ / %@ %@",
                           ASTrimNumber(r.value.doubleValue), ASTrimNumber(r.threshold), r.unit]
              valueColor:[ASDesign dangerColor]];
            [_conditionStack addArrangedSubview:kv];
        }
    }
}

- (void)addNoteToStack:(NSString *)text
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = [ASDesign bodyFont];
    l.textColor = [ASDesign secondaryText];
    l.numberOfLines = 0;
    l.text = text;
    [_conditionStack addArrangedSubview:l];
}

- (void)updateHardwareStatus:(ASSnapshot *)snap
{
    _ledStatus.text = snap.alert.led ? @"Trạng thái: Đang bật" : @"Trạng thái: Đang tắt";
    _buzzerStatus.text = snap.alert.buzzer ? @"Trạng thái: Đang hú còi" : @"Trạng thái: Đang tắt";
    _fanStatus.text = snap.alert.fan ? @"Trạng thái: Đang chạy" : @"Trạng thái: Đang tắt";

    ASThresholds *t = snap.thresholds;
    if (t != nil) {
        if (!_thresholdFields[@"pm2_5"].isFirstResponder) _thresholdFields[@"pm2_5"].text = isnan(t.pm25) ? nil : ASTrimNumber(t.pm25);
        if (!_thresholdFields[@"pm10"].isFirstResponder)  _thresholdFields[@"pm10"].text  = isnan(t.pm10) ? nil : ASTrimNumber(t.pm10);
        if (!_thresholdFields[@"co2"].isFirstResponder)   _thresholdFields[@"co2"].text   = isnan(t.co2)  ? nil : ASTrimNumber(t.co2);
        if (!_thresholdFields[@"lpg"].isFirstResponder)   _thresholdFields[@"lpg"].text   = isnan(t.lpg)  ? nil : ASTrimNumber(t.lpg);
        if (!_thresholdFields[@"co"].isFirstResponder)    _thresholdFields[@"co"].text    = isnan(t.co)   ? nil : ASTrimNumber(t.co);
    }
}

#pragma mark - Commands

- (void)sendCommandTo:(ASSegmentedControl *)control
          statesList:(NSArray<NSString *> *)states
                 text:(NSString *)text
                  run:(void (^)(NSString *state, ASEmptyBlock done))runner
{
    if ([ASMonitor shared].reachability == ASReachabilityOffline) {
        [_banner applyText:@"Mất kết nối — không thể gửi lệnh." symbol:@"wifi.slash" color:[ASDesign dangerColor]];
        [ASDesign hapticError];
        return;
    }
    control.enabled = NO;
    NSString *state = states[MAX(0, MIN(control.selectedIndex, 2))];
    runner(state, ^(NSError *err) {
        control.enabled = YES;
        if (err) {
            [ASDesign hapticError];
            [self->_banner applyText:ASFriendlyErrorMessage(err) symbol:@"exclamationmark.triangle" color:[ASDesign dangerColor]];
        } else {
            [ASDesign hapticSuccess];
            [self->_banner applyText:[NSString stringWithFormat:@"Đã gửi lệnh %@.", state]
                             symbol:@"checkmark.circle" color:[ASDesign goodColor]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self->_banner hide];
            });
        }
        (void)text;
    });
}

- (void)ledChanged:(ASSegmentedControl *)sender
{
    [self sendCommandTo:sender statesList:@[@"off", @"on", @"auto"] text:@"LED"
                   run:^(NSString *state, ASEmptyBlock done) {
        [[ASMonitor shared] setLedState:state completion:done];
    }];
}

- (void)buzzerChanged:(ASSegmentedControl *)sender
{
    [self sendCommandTo:sender statesList:@[@"off", @"on", @"auto"] text:@"Còi"
                   run:^(NSString *state, ASEmptyBlock done) {
        [[ASMonitor shared] setBuzzerState:state completion:done];
    }];
}

- (void)fanChanged:(ASSegmentedControl *)sender
{
    [self sendCommandTo:sender statesList:@[@"off", @"on", @"auto"] text:@"Quạt"
                   run:^(NSString *state, ASEmptyBlock done) {
        [[ASMonitor shared] setFanState:state completion:done];
    }];
}

- (void)saveThreshold:(UIButton *)sender
{
    NSString *key = sender.accessibilityIdentifier;
    UITextField *field = _thresholdFields[key];
    double value = field.text.doubleValue;

    if (field.text.length == 0 || value <= 0) {
        [ASDesign hapticError];
        [_banner applyText:@"Giá trị ngưỡng phải lớn hơn 0." symbol:@"exclamationmark.triangle" color:[ASDesign dangerColor]];
        return;
    }

    sender.enabled = NO;
    [sender setTitle:@"…" forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    [[ASMonitor shared] setThresholdForKey:key value:value completion:^(NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        sender.enabled = YES;
        [sender setTitle:@"Ghi" forState:UIControlStateNormal];
        if (err) {
            [ASDesign hapticError];
            [strongSelf->_banner applyText:ASFriendlyErrorMessage(err) symbol:@"exclamationmark.triangle" color:[ASDesign dangerColor]];
            return;
        }
        [ASDesign hapticSuccess];
        [strongSelf->_banner applyText:[NSString stringWithFormat:@"Đã cập nhật ngưỡng %@ thành %@.", key, ASTrimNumber(value)]
                                symbol:@"checkmark.circle" color:[ASDesign goodColor]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [strongSelf->_banner hide];
        });
    }];
}

- (void)pullToRefresh:(UIRefreshControl *)rc
{
    [[ASMonitor shared] refresh];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [rc endRefreshing];
    });
}

- (void)openGasDetail
{
    [self.navigationController pushViewController:[[ASGasDetailViewController alloc] init] animated:YES];
}

@end