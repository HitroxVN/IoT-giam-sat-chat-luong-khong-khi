// ASSettingsViewController — Device address, Firebase credentials, alert thresholds,
// appearance and refresh. Every control maps to something the backend actually supports;
// nothing here is decorative.
// The Firebase secret is written to the Keychain, never to NSUserDefaults.

#import "UI/ASSettingsViewController.h"
#import "Components/ASComponents.h"
#import "Design/ASDesign.h"
#import "Services/ASSettings.h"
#import "Services/ASMonitor.h"
#import "Models/ASModels.h"
#import "Utils/ASJSON.h"
#import "Services/ASAPIClient.h"
#import "Services/ASNotificationManager.h"

@interface ASSettingsViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@end

@implementation ASSettingsViewController {
    UIScrollView *_scroll;
    UIStackView *_content;

    UITextField *_hostField;
    UITextField *_deviceNameField;
    UITextField *_firebaseURLField;
    UITextField *_secretField;
    UIButton *_secretToggle;

    // Firebase sync controls
    ASSegmentedControl *_firebaseSyncControl;
    UILabel *_firebaseSyncStatus;

    // Calibration controls
    ASGlassCard *_calibrationCard;
    UILabel *_calibrationR0Label;
    UIButton *_calibrateButton;

    // Notification controls
    UISwitch *_notifMasterSwitch;
    UISwitch *_notifWarningSwitch;
    UISwitch *_notifAQISwitch;

    ASSegmentedControl *_appearanceControl;
    ASSegmentedControl *_refreshControl;

    ASGlassCard *_thresholdCard;
    NSMutableDictionary<NSString *, UITextField *> *_thresholdFields;
    NSMutableArray<UIButton *> *_saveButtons;

    ASGlassCard *_aboutCard;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Cài đặt";
    self.view.backgroundColor = [ASDesign ambientBottomForLevel:ASAQILevelUnknown];
    _thresholdFields = [NSMutableDictionary dictionary];
    _saveButtons = [NSMutableArray array];

    [self buildContent];
    [self loadValues];
    [self refreshCalibrationInfo];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(monitorDidUpdate)
                                                 name:ASMonitorDidUpdateNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self loadValues];
    [self refreshCalibrationInfo];
}

- (void)monitorDidUpdate
{
    [self loadValues];
}

#pragma mark - Builders

- (UILabel *)sectionTitle:(NSString *)text
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = [ASDesign microFont];
    l.textColor = [ASDesign tertiaryText];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}

- (UILabel *)bodyText:(NSString *)text
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = [ASDesign captionFont];
    l.textColor = [ASDesign secondaryText];
    l.numberOfLines = 0;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}

- (UITextField *)makeFieldWithPlaceholder:(NSString *)placeholder secure:(BOOL)secure
{
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectZero];
    f.placeholder = placeholder;
    f.font = [ASDesign bodyFont];
    f.textColor = [ASDesign primaryText];
    f.backgroundColor = [[ASDesign primaryText] colorWithAlphaComponent:0.06];
    f.layer.cornerRadius = 12;
    f.layer.cornerCurve = kCACornerCurveContinuous;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.secureTextEntry = secure;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    f.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    f.leftView = pad;
    f.leftViewMode = UITextFieldViewModeAlways;

    [NSLayoutConstraint activateConstraints:@[
        [f.heightAnchor constraintEqualToConstant:44],
    ]];
    return f;
}

- (ASGlassCard *)makeCard
{
    ASGlassCard *c = [[ASGlassCard alloc] initWithEmphasis:NO];
    return c;
}

- (void)buildContent
{
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.alwaysBounceVertical = YES;
    _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:_scroll];

    _content = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _content.axis = UILayoutConstraintAxisVertical;
    _content.spacing = [ASDesign stackSpacing];
    _content.translatesAutoresizingMaskIntoConstraints = NO;
    _content.layoutMarginsRelativeArrangement = YES;
    _content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, [ASDesign cardInset], 34, [ASDesign cardInset]);
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

    [self buildDeviceCard];
    [self buildCalibrationCard];
    [self buildFirebaseCard];
    [self buildThresholdCard];
    [self buildNotificationCard];
    [self buildAppearanceCard];
    [self buildAboutCard];
}

- (void)buildDeviceCard
{
    [_content addArrangedSubview:[self sectionTitle:@"THIẾT BỊ"]];

    ASGlassCard *card = [self makeCard];
    UILabel *note = [self bodyText:@"ESP32 chỉ phục vụ JSON, không có mDNS. IP do router cấp và có thể đổi sau mỗi lần khởi động lại — IP in ra Serial Monitor khi WiFi kết nối."];

    _deviceNameField = [self makeFieldWithPlaceholder:@"Tên hiển thị" secure:NO];
    _hostField = [self makeFieldWithPlaceholder:@"192.168.1.100" secure:NO];
    _hostField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;

    UIButton *save = [ASGlassButton primaryButtonWithTitle:@"Lưu & kết nối" symbol:@"checkmark"];
    [save addTarget:self action:@selector(saveDeviceSettings) forControlEvents:UIControlEventTouchUpInside];

    UIButton *test = [ASGlassButton secondaryButtonWithTitle:@"Kiểm tra kết nối" symbol:@"bolt.horizontal"];
    [test addTarget:self action:@selector(testConnection) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *fields = [[UIStackView alloc] initWithArrangedSubviews:@[_deviceNameField, _hostField]];
    fields.axis = UILayoutConstraintAxisVertical;
    fields.spacing = 10;

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[save, test]];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[note, fields, buttons]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:card];
}

- (void)buildCalibrationCard
{
    [_content addArrangedSubview:[self sectionTitle:@"HIỆU CHUẨN CẢM BIẾN (R0)"]];

    _calibrationCard = [self makeCard];
    UILabel *note = [self bodyText:@"POST /api/calibrate — ESP32 đo lại R0 cho 3 cảm biến MQ trong không khí sạch và lưu vào bộ nhớ hoạt động. Chỉ thực hiện khi cảm biến đã được làm nóng 5-10 phút."];

    _calibrationR0Label = [self bodyText:@"Đang lấy thông số R0..."];
    _calibrationR0Label.font = [ASDesign captionFont];
    _calibrationR0Label.textColor = [ASDesign primaryText];

    _calibrateButton = [ASGlassButton primaryButtonWithTitle:@"Hiệu chuẩn R0 (Không khí sạch)" symbol:@"sparkles"];
    [_calibrateButton addTarget:self action:@selector(calibrateTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *refreshCal = [ASGlassButton secondaryButtonWithTitle:@"Đọc lại R0" symbol:@"arrow.clockwise"];
    [refreshCal addTarget:self action:@selector(refreshCalibrationInfo) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *calButtons = [[UIStackView alloc] initWithArrangedSubviews:@[_calibrateButton, refreshCal]];
    calButtons.axis = UILayoutConstraintAxisVertical;
    calButtons.spacing = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[note, _calibrationR0Label, calButtons]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_calibrationCard addSubview:stack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:_calibrationCard.topAnchor constant:inset],
        [stack.bottomAnchor constraintEqualToAnchor:_calibrationCard.bottomAnchor constant:-inset],
        [stack.leadingAnchor constraintEqualToAnchor:_calibrationCard.leadingAnchor constant:inset],
        [stack.trailingAnchor constraintEqualToAnchor:_calibrationCard.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_calibrationCard];
}

- (void)buildFirebaseCard
{
    [_content addArrangedSubview:[self sectionTitle:@"FIREBASE — NGUỒN LỊCH SỬ"]];

    ASGlassCard *card = [self makeCard];
    UILabel *note = [self bodyText:@"ESP32 không có endpoint lịch sử. Khi firmware đẩy dữ liệu lên Firebase Realtime Database, ứng dụng đọc esp32/history bằng REST. Secret được lưu trong Keychain của iOS, không ghi vào tệp cấu hình."];

    _firebaseURLField = [self makeFieldWithPlaceholder:@"https://ten-cua-ban.firebaseio.com" secure:NO];
    _firebaseURLField.keyboardType = UIKeyboardTypeURL;
    _firebaseURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;

    _secretField = [self makeFieldWithPlaceholder:@"Database secret" secure:YES];
    _secretField.textContentType = UITextContentTypePassword;

    _secretToggle = [ASGlassButton secondaryButtonWithTitle:@"Hiện secret" symbol:@"eye"];
    [_secretToggle addTarget:self action:@selector(toggleSecretVisibility) forControlEvents:UIControlEventTouchUpInside];

    UIButton *save = [ASGlassButton primaryButtonWithTitle:@"Lưu thông tin Firebase" symbol:@"checkmark"];
    [save addTarget:self action:@selector(saveFirebaseSettings) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *fields = [[UIStackView alloc] initWithArrangedSubviews:@[_firebaseURLField, _secretField]];
    fields.axis = UILayoutConstraintAxisVertical;
    fields.spacing = 10;

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[_secretToggle, save]];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 8;

    UILabel *syncTitle = [self bodyText:@"Đồng bộ dữ liệu thời gian thực:"];
    syncTitle.font = [ASDesign headlineFont];
    syncTitle.textColor = [ASDesign primaryText];

    _firebaseSyncControl = [[ASSegmentedControl alloc] initWithFrame:CGRectZero];
    [_firebaseSyncControl setTitles:@[@"Tắt", @"Bật"] selectedIndex:0];
    _firebaseSyncControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_firebaseSyncControl addTarget:self action:@selector(firebaseSyncChanged:) forControlEvents:UIControlEventValueChanged];

    _firebaseSyncStatus = [self bodyText:@"Đang đọc trạng thái đồng bộ..."];
    _firebaseSyncStatus.textAlignment = NSTextAlignmentCenter;

    UIStackView *syncSection = [[UIStackView alloc] initWithArrangedSubviews:@[syncTitle, _firebaseSyncControl, _firebaseSyncStatus]];
    syncSection.axis = UILayoutConstraintAxisVertical;
    syncSection.spacing = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[note, fields, buttons, syncSection]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [_firebaseSyncControl.heightAnchor constraintEqualToConstant:36],
    ]];
    [_content addArrangedSubview:card];
}

- (void)buildThresholdCard
{
    [_content addArrangedSubview:[self sectionTitle:@"NGƯỠNG CẢNH BÁO"]];
    _thresholdCard = [self makeCard];

    UILabel *note = [self bodyText:@"Các giá trị ngưỡng dùng để tự động kích hoạt cảnh báo và điều khiển Đèn, Còi, Quạt. Thay đổi sẽ có hiệu lực ngay trên thiết bị mà không cần nạp lại firmware."];

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
        [label.widthAnchor constraintEqualToConstant:132].active = YES;

        UITextField *field = [self makeFieldWithPlaceholder:@"—" secure:NO];
        field.keyboardType = UIKeyboardTypeDecimalPad;
        field.tag = 400;
        field.accessibilityIdentifier = spec[0];
        _thresholdFields[spec[0]] = field;

        UIButton *save = [ASGlassButton primaryButtonWithTitle:@"Ghi" symbol:@"arrow.up.circle"];
        save.tag = 500;
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

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[note, rows]];
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

- (UIView *)makeSwitchRowWithTitle:(NSString *)title subtitle:(NSString *)sub control:(UISwitch *)sw
{
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [self labelWithText:title font:[ASDesign bodyFont] color:[ASDesign primaryText]];
    UILabel *subLabel = [self labelWithText:sub font:[ASDesign microFont] color:[ASDesign tertiaryText]];

    UIStackView *labelStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subLabel]];
    labelStack.axis = UILayoutConstraintAxisVertical;
    labelStack.spacing = 2;
    labelStack.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:labelStack];

    sw.translatesAutoresizingMaskIntoConstraints = NO;
    sw.onTintColor = [ASDesign goodColor];
    [row addSubview:sw];

    [NSLayoutConstraint activateConstraints:@[
        [labelStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [labelStack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [labelStack.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-12],

        [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    return row;
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = font;
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

- (void)buildNotificationCard
{
    [_content addArrangedSubview:[self sectionTitle:@"THÔNG BÁO ĐẨY"]];

    ASGlassCard *card = [self makeCard];
    UILabel *note = [self bodyText:@"Gửi thông báo đẩy khi thiết bị thay đổi trạng thái (vượt ngưỡng nguy hiểm, chạm cảnh báo 80%, hoặc chỉ số AQI chuyển xấu)."];

    _notifMasterSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_notifMasterSwitch addTarget:self action:@selector(notificationMasterChanged:) forControlEvents:UIControlEventValueChanged];
    UIView *masterRow = [self makeSwitchRowWithTitle:@"Bật thông báo"
                                            subtitle:@"Nhận thông báo khi phát hiện nguy cơ"
                                             control:_notifMasterSwitch];

    _notifWarningSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_notifWarningSwitch addTarget:self action:@selector(notificationWarningChanged:) forControlEvents:UIControlEventValueChanged];
    UIView *warningRow = [self makeSwitchRowWithTitle:@"Cảnh báo sớm (≥ 80%)"
                                             subtitle:@"Thông báo khi nồng độ chạm ngưỡng cảnh báo trước khi kích hoạt còi/quạt"
                                              control:_notifWarningSwitch];

    _notifAQISwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_notifAQISwitch addTarget:self action:@selector(notificationAQIChanged:) forControlEvents:UIControlEventValueChanged];
    UIView *aqiRow = [self makeSwitchRowWithTitle:@"Chuyển mức AQI xấu"
                                         subtitle:@"Thông báo khi chỉ số AQI chuyển sang mức Kém / Xấu / Nguy hại"
                                          control:_notifAQISwitch];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[note, masterRow, warningRow, aqiRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:card];
}

- (void)buildAppearanceCard
{
    [_content addArrangedSubview:[self sectionTitle:@"GIAO DIỆN & LÀM MỚI"]];

    ASGlassCard *card = [self makeCard];

    UILabel *appearanceLabel = [self bodyText:@"Giao diện"];
    _appearanceControl = [[ASSegmentedControl alloc] initWithFrame:CGRectZero];
    [_appearanceControl setTitles:@[@"Theo hệ thống", @"Sáng", @"Tối"] selectedIndex:0];
    _appearanceControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_appearanceControl addTarget:self action:@selector(appearanceChanged:)
                 forControlEvents:UIControlEventValueChanged];

    UILabel *refreshLabel = [self bodyText:@"Làm mới tự động"];
    _refreshControl = [[ASSegmentedControl alloc] initWithFrame:CGRectZero];
    [_refreshControl setTitles:@[@"Tắt", @"15s", @"30s", @"60s"] selectedIndex:2];
    _refreshControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_refreshControl addTarget:self action:@selector(refreshChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        appearanceLabel, _appearanceControl, refreshLabel, _refreshControl]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [_appearanceControl.heightAnchor constraintEqualToConstant:36],
        [_refreshControl.heightAnchor constraintEqualToConstant:36],
    ]];
    [_content addArrangedSubview:card];
}

- (void)buildAboutCard
{
    _aboutCard = [self makeCard];
    UILabel *note = [self bodyText:
        @"AirSense 1.0.0\n"
        @"Đọc toàn bộ dữ liệu từ REST API của ESP32 theo tài liệu API.md. Không có dữ liệu mô phỏng: "
        @"mọi giá trị hiển thị đều đến từ thiết bị, Firebase, hoặc nhật ký ghi trên máy này.\n\n"
        @"AQI được tính từ PM2.5 theo công thức US EPA vì ESP32 không cung cấp trường AQI. "
        @"Độ chính xác phụ thuộc vào việc hiệu chỉnh cảm biến, không phải chỉ số đo chính thức."];
    note.translatesAutoresizingMaskIntoConstraints = NO;
    [_aboutCard addSubview:note];

    CGFloat inset = [ASDesign cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [note.topAnchor constraintEqualToAnchor:_aboutCard.topAnchor constant:inset],
        [note.bottomAnchor constraintEqualToAnchor:_aboutCard.bottomAnchor constant:-inset],
        [note.leadingAnchor constraintEqualToAnchor:_aboutCard.leadingAnchor constant:inset],
        [note.trailingAnchor constraintEqualToAnchor:_aboutCard.trailingAnchor constant:-inset],
    ]];
    [_content addArrangedSubview:_aboutCard];
}

#pragma mark - Load / save

- (void)loadValues
{
    ASSettings *cfg = [ASSettings shared];
    _deviceNameField.text = cfg.deviceName;
    _hostField.text = cfg.espHost;
    _firebaseURLField.text = cfg.firebaseDatabaseURL;
    _secretField.text = cfg.firebaseSecret;

    [_appearanceControl setSelectedIndexSilently:cfg.appearanceMode];
    [_refreshControl setSelectedIndexSilently:cfg.refreshInterval == 0 ? 0
                                       : (cfg.refreshInterval == 15 ? 1
                                       : (cfg.refreshInterval == 30 ? 2 : 3))];

    _notifMasterSwitch.on = cfg.notificationsEnabled;
    _notifWarningSwitch.on = cfg.notifyWarning;
    _notifAQISwitch.on = cfg.notifyAQI;
    _notifWarningSwitch.enabled = cfg.notificationsEnabled;
    _notifAQISwitch.enabled = cfg.notificationsEnabled;

    ASSnapshot *snap = [ASMonitor shared].snapshot;
    if (snap == nil) return;
    ASThresholds *t = snap.thresholds;
    _thresholdFields[@"pm2_5"].text = isnan(t.pm25) ? nil : ASTrimNumber(t.pm25);
    _thresholdFields[@"pm10"].text  = isnan(t.pm10) ? nil : ASTrimNumber(t.pm10);
    _thresholdFields[@"co2"].text   = isnan(t.co2)  ? nil : ASTrimNumber(t.co2);
    _thresholdFields[@"lpg"].text   = isnan(t.lpg)  ? nil : ASTrimNumber(t.lpg);
    _thresholdFields[@"co"].text    = isnan(t.co)   ? nil : ASTrimNumber(t.co);

    if (snap.firebase != nil) {
        [_firebaseSyncControl setSelectedIndexSilently:snap.firebase.enabled ? 1 : 0];
        _firebaseSyncStatus.text = [NSString stringWithFormat:@"%@ · chu kỳ %.0f giây",
            snap.firebase.enabled ? @"Đồng bộ Firebase: Bật" : @"Đồng bộ Firebase: Tắt",
            snap.firebase.intervalMs.doubleValue / 1000.0];
    }
}

- (void)saveDeviceSettings
{
    ASSettings *cfg = [ASSettings shared];
    cfg.deviceName = _deviceNameField.text;
    cfg.espHost = [_hostField.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (!cfg.isConfigured) {
        [self showAlertWithTitle:@"Địa chỉ chưa hợp lệ"
                         message:@"Nhập IP của ESP32, ví dụ 192.168.1.100. Có thể kèm cổng, ví dụ 192.168.1.100:8080."];
        return;
    }
    [ASDesign hapticSuccess];
    [[ASMonitor shared] refresh];
    [self showAlertWithTitle:@"Đã lưu" message:@"Ứng dụng đang kết nối tới ESP32."];
}

- (void)saveFirebaseSettings
{
    ASSettings *cfg = [ASSettings shared];
    cfg.firebaseDatabaseURL = [_firebaseURLField.text stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    cfg.firebaseSecret = _secretField.text;

    if (cfg.firebaseDatabaseURL.length && !cfg.firebaseSecret.length) {
        [self showAlertWithTitle:@"Thiếu secret"
                         message:@"Database secret là thông tin nhạy cảm — được lưu trong Keychain của iOS, không nằm trong tệp cấu hình."];
        return;
    }
    [ASDesign hapticSuccess];
    [cfg applyToClient:[ASMonitor shared].client];
    [self showAlertWithTitle:@"Đã lưu Firebase"
                     message:cfg.firebaseConfigured
                        ? @"Lịch sử sẽ đọc từ esp32/history. Gạt công tắc Bật bên dưới để ESP32 bắt đầu ghi dữ liệu."
                        : @"Đã xoá cấu hình Firebase."];
}

- (void)firebaseSyncChanged:(ASSegmentedControl *)sender
{
    NSString *state = sender.selectedIndex == 1 ? @"on" : @"off";
    sender.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [[ASMonitor shared] setFirebaseState:state completion:^(NSError *err) {
        sender.enabled = YES;
        if (err) {
            [ASDesign hapticError];
            [weakSelf showAlertWithTitle:@"Không gửi được lệnh" message:ASFriendlyErrorMessage(err)];
            return;
        }
        [ASDesign hapticSuccess];
        [weakSelf showAlertWithTitle:@"Thành công" message:[NSString stringWithFormat:@"Đồng bộ Firebase: %@", state]];
    }];
}

#pragma mark - Calibration

- (void)refreshCalibrationInfo
{
    __weak typeof(self) weakSelf = self;
    [[ASMonitor shared].client fetchCalibrationWithCompletion:^(NSDictionary *info, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (err || info == nil) {
            ASGasReading *gas = [ASMonitor shared].gasReading;
            if (gas && gas.sensors.count > 0) {
                NSMutableString *str = [NSMutableString stringWithString:@"Hệ số R0 hiện tại:\n"];
                for (ASGasSensor *s in gas.sensors) {
                    [str appendFormat:@"• %@ (%@): R0 = %@\n",
                        s.key.uppercaseString, s.gas, s.r0 ? ASTrimNumber(s.r0.doubleValue) : @"—"];
                }
                strongSelf->_calibrationR0Label.text = [str stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            } else {
                strongSelf->_calibrationR0Label.text = @"Chưa đọc được thông tin R0 từ thiết bị.";
            }
            return;
        }

        NSMutableString *str = [NSMutableString stringWithString:@"Hệ số R0 hiện tại:\n"];
        NSDictionary *mq135 = info[@"mq135"];
        NSDictionary *mq2   = info[@"mq2"];
        NSDictionary *mq7   = info[@"mq7"];
        if ([mq135 isKindOfClass:[NSDictionary class]]) {
            [str appendFormat:@"• MQ-135 (CO₂): R0 = %@\n", ASTrimNumber([mq135[@"r0"] doubleValue])];
        }
        if ([mq2 isKindOfClass:[NSDictionary class]]) {
            [str appendFormat:@"• MQ-2 (LPG): R0 = %@\n", ASTrimNumber([mq2[@"r0"] doubleValue])];
        }
        if ([mq7 isKindOfClass:[NSDictionary class]]) {
            [str appendFormat:@"• MQ-7 (CO): R0 = %@\n", ASTrimNumber([mq7[@"r0"] doubleValue])];
        }
        strongSelf->_calibrationR0Label.text = [str stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    }];
}

- (void)calibrateTapped:(UIButton *)sender
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hiệu chuẩn R0"
                                                                   message:@"Cần đảm bảo cảm biến MQ đã được làm nóng (warm-up) tối thiểu 5-10 phút và thiết bị đang ở ngoài trời hoặc phòng thoáng khí sạch.\n\nESP32 sẽ lấy 30 mẫu đọc trong không khí sạch để tính R0 mới."
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
        [strongSelf->_calibrateButton setTitle:@"Hiệu chuẩn R0 (Không khí sạch)" forState:UIControlStateNormal];

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
        [strongSelf refreshCalibrationInfo];
    }];
}

- (void)toggleSecretVisibility
{
    BOOL hidden = _secretField.isSecureTextEntry;
    _secretField.secureTextEntry = !hidden;
    [_secretToggle setTitle:hidden ? @"Ẩn secret" : @"Hiện secret" forState:UIControlStateNormal];
}

- (void)saveThreshold:(UIButton *)sender
{
    NSString *key = sender.accessibilityIdentifier;
    UITextField *field = _thresholdFields[key];
    double value = field.text.doubleValue;

    if (field.text.length == 0 || value <= 0) {
        [self showAlertWithTitle:@"Giá trị không hợp lệ" message:@"Ngưỡng phải là số lớn hơn 0."];
        return;
    }

    sender.enabled = NO;
    [sender setTitle:@"…" forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    [[ASMonitor shared] setThresholdForKey:key value:value completion:^(NSError *err) {
        sender.enabled = YES;
        [sender setTitle:@"Ghi" forState:UIControlStateNormal];
        if (err) {
            [ASDesign hapticError];
            [weakSelf showAlertWithTitle:@"Không ghi được ngưỡng" message:ASFriendlyErrorMessage(err)];
            return;
        }
        [ASDesign hapticSuccess];
    }];
}

- (void)notificationMasterChanged:(UISwitch *)sender
{
    ASSettings *cfg = [ASSettings shared];
    cfg.notificationsEnabled = sender.isOn;
    _notifWarningSwitch.enabled = sender.isOn;
    _notifAQISwitch.enabled = sender.isOn;
    [ASDesign hapticLight];

    if (sender.isOn) {
        [[ASNotificationManager shared] requestAuthorizationWithCompletion:^(BOOL granted) {
            if (!granted) {
                // If denied in iOS system settings, inform user
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showAlertWithTitle:@"Chưa cấp quyền thông báo"
                                     message:@"Vui lòng cho phép quyền Thông báo cho AirSense trong Cài đặt của iPhone để nhận cảnh báo."];
                });
            }
        }];
    }
}

- (void)notificationWarningChanged:(UISwitch *)sender
{
    [ASSettings shared].notifyWarning = sender.isOn;
    [ASDesign hapticLight];
}

- (void)notificationAQIChanged:(UISwitch *)sender
{
    [ASSettings shared].notifyAQI = sender.isOn;
    [ASDesign hapticLight];
}

- (void)appearanceChanged:(ASSegmentedControl *)sender
{
    ASSettings *cfg = [ASSettings shared];
    cfg.appearanceMode = sender.selectedIndex;
    [ASDesign hapticLight];
    // Post so the app delegate can apply the new override.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ASAppearanceDidChange" object:nil];
}

- (void)refreshChanged:(ASSegmentedControl *)sender
{
    ASSettings *cfg = [ASSettings shared];
    NSInteger seconds = 0;
    switch (sender.selectedIndex) {
        case 1: seconds = 15; break;
        case 2: seconds = 30; break;
        case 3: seconds = 60; break;
        default: seconds = 0; break;
    }
    cfg.refreshInterval = seconds;
    [[ASMonitor shared] stopPolling];
    [[ASMonitor shared] startPolling];
    [ASDesign hapticLight];
}

- (void)testConnection
{
    ASSettings *cfg = [ASSettings shared];
    cfg.espHost = [_hostField.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!cfg.isConfigured) {
        [self showAlertWithTitle:@"Địa chỉ chưa hợp lệ" message:@"Cần một IP hoặc tên máy chủ hợp lệ."];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSURL *url = [ASAPIClient baseURLFromHost:cfg.espHost];
    NSURLSession *session = [NSURLSession sharedSession];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/api/data", url.absoluteString]]];
    req.timeoutInterval = 6;

    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [weakSelf showAlertWithTitle:@"Không kết nối được" message:ASFriendlyErrorMessage(error)];
                return;
            }
            NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
            if (status == 200) {
                [ASDesign hapticSuccess];
                [weakSelf showAlertWithTitle:@"Kết nối thành công"
                                     message:@"ESP32 trả lời bình thường cho GET /api/data."];
            } else {
                [weakSelf showAlertWithTitle:[NSString stringWithFormat:@"Máy chủ trả về %ld", (long)status]
                                     message:@"Thiết bị đã phản hồi nhưng trả mã lỗi. Kiểm tra lại firmware hoặc đường dẫn."];
            }
        });
    }] resume];
}

#pragma mark - Helpers

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                                message:message
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

@end