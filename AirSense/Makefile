TARGET := iphone:clang:latest
ARCHS = arm64
TARGET_OS_DEPLOYMENT_VERSION = 16.0
INSTALL_TARGET_PROCESSES = AirSense

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = AirSense

# Source files are organized into module directories.
AirSense_FILES = Application/main.m \
	Application/ASAppDelegate.m \
	Application/ASCrashLog.m \
	Application/ASRootViewController.m \
	Design/ASDesign.m \
	Components/ASComponents.m \
	Components/ASChartView.m \
	Utils/ASJSON.m \
	Models/ASModels.m \
	Models/ASHistory.m \
	Services/ASAPIClient.m \
	Services/ASSettings.m \
	Services/ASNotificationManager.m \
	Services/ASMonitor.m \
	UI/ASDashboardViewController.m \
	UI/ASAirQualityViewController.m \
	UI/ASGasDetailViewController.m \
	UI/ASHistoryViewController.m \
	UI/ASAlertsViewController.m \
	UI/ASSettingsViewController.m

AirSense_FRAMEWORKS = UIKit CoreGraphics UserNotifications
AirSense_CFLAGS = -fobjc-arc -I.

include $(THEOS_MAKE_PATH)/application.mk
