APP_NAME := SystemPulse
APP_DIR := dist/$(APP_NAME).app
MODULE_CACHE := /private/tmp/systempulse-swift-module-cache
PERFORMANCE_OUTPUT_DIR ?= /tmp

.PHONY: run build test unit-test check lint format measure-performance bundle zip verify-zip install clean

run:
	SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE) swift run

# Assemble the .app and replace ~/Applications/SystemPulse.app.
build:
	SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE) ./scripts/build-app.sh

bundle: build

test:
	./scripts/test-app-bundle.sh

unit-test:
	SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE) swift test

check: unit-test
	SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE) swift build -Xswiftc -warnings-as-errors

# Standard Swift formatter ships with recent Xcode/Command Line Tools.
lint:
	xcrun swift-format lint --strict --recursive Sources Tests
	xcrun swift-format lint --strict scripts/measure-running-app.swift
	bash -n scripts/measure-running-app.sh scripts/measure-performance.sh

format:
	xcrun swift-format format --in-place --recursive Sources Tests
	xcrun swift-format format --in-place scripts/measure-running-app.swift

# Opt-in release CPU/footprint/wakeup proxy matrix; no app installation or permissions.
measure-performance:
	./scripts/measure-performance.sh --output-dir "$(PERFORMANCE_OUTPUT_DIR)"

zip:
	./scripts/package-zip.sh

verify-zip:
	./scripts/verify-committed-zip.sh

install:
	./install.sh

clean:
	rm -rf .build dist
