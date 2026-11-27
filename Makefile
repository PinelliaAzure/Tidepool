# Tidepool 构建快捷方式
#
# 纯 Command Line Tools 环境下，macOS 27 SDK 的 SwiftUI 依赖缺失的
# SwiftUIMacros 插件，因此自动回退到 MacOSX26.5 SDK（安装了完整 Xcode 则不需要）。

CLT_SDKS := /Library/Developer/CommandLineTools/SDKs
# 以当前生效的 developer 目录为准：xcode-select 指向 CLT 时（即使装了完整 Xcode）
# 仍需回退 SDK，避免 macOS 27 SDK 缺 SwiftUIMacros 插件。
DEVELOPER_DIR := $(shell xcode-select -p 2>/dev/null)

ifeq ($(findstring CommandLineTools,$(DEVELOPER_DIR)),CommandLineTools)
  # 与 build-app.sh 保持一致：显式列出可用的 26.x SDK，避免通配到未来版本。
  FALLBACK_SDK := $(firstword $(wildcard $(CLT_SDKS)/MacOSX26.5.sdk $(CLT_SDKS)/MacOSX26.sdk))
  ifneq ($(FALLBACK_SDK),)
    export SDKROOT := $(FALLBACK_SDK)
  endif
endif

.PHONY: build test run preview app dmg clean

build:
	swift build

test:
	swift test

run:
	swift run

preview:
	swift run Tidepool --preview

app:
	./build-app.sh

dmg:
	./Scripts/make-dmg.sh

clean:
	swift package clean
	rm -rf build
