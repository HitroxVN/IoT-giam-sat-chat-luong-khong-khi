#import "Application/ASAppDelegate.h"
#import "Application/ASRootViewController.h"
#import "Services/ASSettings.h"
#import "Services/ASMonitor.h"
#import "Services/ASNotificationManager.h"
#import "Application/ASCrashLog.h"

@implementation ASAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Capture crashes before anything else can go wrong.
    [[ASCrashLog shared] install];

    // Settings first: the monitor needs the host and the polling interval at init.
    ASSettings *settings = [ASSettings shared];
    [settings applyToClient:[ASMonitor shared].client];

    // If notifications are enabled, request authorization early
    if (settings.notificationsEnabled) {
        [[ASNotificationManager shared] requestAuthorizationWithCompletion:nil];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appearanceDidChange)
                                                 name:@"ASAppearanceDidChange"
                                               object:nil];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [self applyAppearance];
    self.window.rootViewController = [[ASRootViewController alloc] init];
    [self.window makeKeyAndVisible];

    [[ASMonitor shared] startPolling];
    return YES;
}

- (void)applyAppearance
{
    ASAppearance mode = [ASSettings shared].appearanceMode;
    self.window.overrideUserInterfaceStyle =
        mode == ASAppearanceDark ? UIUserInterfaceStyleDark
      : (mode == ASAppearanceLight ? UIUserInterfaceStyleLight : UIUserInterfaceStyleUnspecified);
}

- (void)appearanceDidChange
{
    [self applyAppearance];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [[ASMonitor shared] stopPolling];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [[ASMonitor shared] startPolling];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end