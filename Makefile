ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SFSkipSplash

SFSkipSplash_FILES = Tweak.xm
SFSkipSplash_CFLAGS = -fobjc-arc
SFSkipSplash_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
