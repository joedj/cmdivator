TARGET := iphone:clang::5.0
ARCHS := armv7 arm64

ifdef CCC_ANALYZER_OUTPUT_FORMAT
  TARGET_CXX = $(CXX)
  TARGET_LD = $(TARGET_CXX)
endif

ADDITIONAL_CFLAGS += -g -fobjc-arc -fvisibility=hidden
ADDITIONAL_LDFLAGS += -g -fobjc-arc -x c /dev/null -x none

TWEAK_NAME = Cmdivator

Cmdivator_FILES = Tweak.m
Cmdivator_LIBRARIES = activator

include theos/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) \( -iname '*.plist' -or -iname '*.strings' \) -exec plutil -convert binary1 {} \;$(ECHO_END)
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) -d -name '*.dSYM' -execdir rm -rf {} \;$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/Cmdivator/Cmds$(ECHO_END)

after-install::
	install.exec "(killall backboardd || killall SpringBoard) 2>/dev/null"

after-clean::
	rm -f *.deb
