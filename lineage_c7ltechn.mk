#
# LineageOS product makefile for Samsung Galaxy C7 (SM-C7000 / c7ltechn)
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from c7ltechn device
$(call inherit-product, device/samsung/c7ltechn/device.mk)

# Inherit some common LineageOS stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Device identifier. This must come after all inclusions
PRODUCT_DEVICE := c7ltechn
PRODUCT_NAME := lineage_c7ltechn
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-C7000
PRODUCT_MANUFACTURER := samsung

PRODUCT_CHARACTERISTICS := nosdcard

PRODUCT_GMS_CLIENTID_BASE := android-samsung

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRODUCT_NAME=c7ltezc \
    BUILD_FINGERPRINT=samsung/c7ltezc/c7ltechn:8.0.0/R16NW/C7000ZCS3CRJ1:user/release-keys \
    PRIVATE_BUILD_DESC="c7ltezc-user 8.0.0 R16NW C7000ZCS3CRJ1 release-keys"
