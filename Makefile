# Tidepool 构建快捷方式
#
# 纯 Command Line Tools 环境下，macOS 27 SDK 的 SwiftUI 依赖缺失的
# SwiftUIMacros 插件，因此自动回退到 MacOSX26.5 SDK（安装了完整 Xcode 则不需要）。

CLT_SDKS := /Library/Developer/CommandLineTools/SDKs
XCODE_APPS := $(wildcard /Applications/Xcode*.app)

ifeq ($(XCODE_APPS),)
  FALLBACK_SDK := $(lastword $(sort $(wildcard $(CLT_SDKS)/MacOSX2[0-6]*.sdk)))
  ifneq ($(FALLBACK_SDK),)
    export SDKROOT := $(FALLBACK_SDK)
  endif
endif

.PHONY: build test run app clean

build:
	swift build

test:
	swift test

run:
	swift run

app:
	./build-app.sh

clean:
	swift package clean
	rm -rf build
