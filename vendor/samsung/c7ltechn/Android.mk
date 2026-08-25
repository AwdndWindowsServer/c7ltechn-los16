LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),c7ltechn)
include $(call all-makefiles-under,$(LOCAL_PATH))
endif
