TARGET := iphone:clang::5.0
ARCHS := armv7 arm64

ifdef CCC_ANALYZER_OUTPUT_FORMAT
  TARGET_CXX = $(CXX)
  TARGET_LD = $(TARGET_CXX)
endif

ADDITIONAL_CFLAGS += -g -fobjc-arc -fvisibility=hidden
ADDITIONAL_LDFLAGS += -g -fobjc-arc -Wl,-map,$@.map -x c /dev/null -x none

TWEAK_NAME = Cmdivator
Cmdivator_FILES = Cmdivator.m CmdivatorCmd.m CmdivatorScanner.m CmdivatorDirectoryEnumerator.m
Cmdivator_LIBRARIES = activator
Cmdivator_FRAMEWORKS = UIKit
Cmdivator_PRIVATE_FRAMEWORKS = AppSupport

BUNDLE_NAME = Settings
Settings_FILES = Settings.m
Settings_LIBRARIES = activator
Settings_FRAMEWORKS = UIKit
Settings_PRIVATE_FRAMEWORKS = AppSupport Preferences
Settings_INSTALL_PATH = /Library/PreferenceBundles

include theos/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-stage::
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) \( -iname '*.plist' -or -iname '*.strings' \) -exec plutil -convert binary1 {} \;$(ECHO_END)
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) -d \( -iname '*.dSYM' -or -iname '*.map' \) -execdir rm -rf {} \;$(ECHO_END)
	$(ECHO_NOTHING)mv $(THEOS_STAGING_DIR)$(Settings_INSTALL_PATH)/$(BUNDLE_NAME).bundle/$(BUNDLE_NAME) $(THEOS_STAGING_DIR)$(Settings_INSTALL_PATH)/$(BUNDLE_NAME).bundle/$(TWEAK_NAME)$(ECHO_END)
	$(ECHO_NOTHING)mv $(THEOS_STAGING_DIR)$(Settings_INSTALL_PATH)/$(BUNDLE_NAME).bundle $(THEOS_STAGING_DIR)$(Settings_INSTALL_PATH)/$(TWEAK_NAME).bundle$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/Cmdivator/Cmds$(ECHO_END)
	$(ECHO_NOTHING)cp LICENSE README.md $(THEOS_STAGING_DIR)/Library/Cmdivator$(ECHO_END)

after-install::
	install.exec "(killall backboardd || killall SpringBoard) 2>/dev/null"

after-clean::
	rm -f *.deb
