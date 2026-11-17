ARCHS = arm64
# Theos TARGET 格式：iphone:编译器:SDK版本:最低系统版本
# 与 CI 中 theos/sdks 提供的 iPhoneOS16.5.sdk 对齐
TARGET = iphone:clang:16.5:13.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SaoqiangWCAssets

SaoqiangWCAssets_FILES = $(wildcard Sources/*.m)
SaoqiangWCAssets_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore ImageIO CoreFoundation UniformTypeIdentifiers
SaoqiangWCAssets_LIBRARIES = z
SaoqiangWCAssets_CFLAGS = -fobjc-arc -Wno-unused-parameter -Wno-deprecated-declarations
SaoqiangWCAssets_LDFLAGS = -Wl,-rpath,@executable_path/Frameworks

include $(THEOS_MAKE_PATH)/tweak.mk

# 真机签名 entitlements 在注入阶段用 ldid 单独处理（见 README），不在此处指定，
# 以免 Theos 打包阶段因证书/权限参数报错。

# TrollStore 说明：
#   本工程不使用 CydiaSubstrate / Substitute，无需 mobilesubstrate 依赖。
#   用 Theos 编译出 .dylib 后，将其注入解密后的 WeChat IPA：
#     insert_dylib --strip-codesig --inplace @executable_path/Frameworks/SaoqiangWCAssets.dylib WeChat
#   再用 ldid 签名并赋予 TrollStore 所需 entitlements，最后通过 TrollStore 安装 IPA。
