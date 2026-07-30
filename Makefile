APP_NAME := SystemPulse
APP_DIR := dist/$(APP_NAME).app
MODULE_CACHE := /private/tmp/systempulse-swift-module-cache

.PHONY: run build test bundle zip verify-zip install clean

run:
	SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE) swift run

build:
	SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE) swift build -c release

test:
	./scripts/test-app-bundle.sh

bundle:
	./scripts/build-app.sh

zip:
	./scripts/package-zip.sh

verify-zip:
	./scripts/verify-committed-zip.sh

install:
	./install.sh

clean:
	rm -rf .build dist
