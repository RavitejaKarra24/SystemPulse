APP_NAME := SystemPulse
BUILD_DIR := .build/release
APP_DIR := dist/$(APP_NAME).app
EXECUTABLE := $(BUILD_DIR)/$(APP_NAME)
MODULE_CACHE := /private/tmp/systempulse-swift-module-cache

.PHONY: run build bundle clean

run:
	SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE) swift run

build:
	SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE) swift build -c release

bundle: build
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	cp "$(EXECUTABLE)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	@echo "Created $(APP_DIR)"

clean:
	rm -rf .build dist
