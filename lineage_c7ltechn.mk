#
# LineageOS product makefile for Samsung Galaxy C7 (SM-C7000 / c7ltechn)
#

$(call inherit-product, device/samsung/c7ltechn/device.mk)

# Device identifier
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
