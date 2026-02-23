BUILD_DIR    = build
APP_NAME     = IPRegionBar
VERSION      = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
               IPRegionBar/App/Info.plist)
APP_BINARY   = $(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)

CODESIGN_IDENTITY ?= -
CODESIGN_EXTRA_FLAGS ?=

.PHONY: build build-universal build-local package-app sign-app verify-universal dmg notarize release release-notarized update-db

build:
	$(MAKE) build-universal

build-universal:
	rm -rf .build
	swift build -c release --arch arm64
	swift build -c release --arch x86_64
	$(MAKE) package-app \
		BINARY_PATH=".build/arm64-apple-macosx/release/$(APP_NAME)" \
		BINARY_PATH_X86=".build/x86_64-apple-macosx/release/$(APP_NAME)"
	$(MAKE) verify-universal

build-local:
	swift build -c release
	$(MAKE) package-app \
		BINARY_PATH=".build/release/$(APP_NAME)"

package-app:
	@test -n "$(BINARY_PATH)"
	rm -rf "$(BUILD_DIR)/$(APP_NAME).app"
	mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS"
	mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources"
	@if [ -n "$(BINARY_PATH_X86)" ]; then \
		lipo -create "$(BINARY_PATH)" "$(BINARY_PATH_X86)" -output "$(APP_BINARY)"; \
	else \
		cp "$(BINARY_PATH)" "$(APP_BINARY)"; \
	fi
	cp "IPRegionBar/App/Info.plist" "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	cp "IPRegionBar/Resources/dbip-city-lite.mmdb" "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources/dbip-city-lite.mmdb"
	cp "IPRegionBar/Resources/dbip-city-lite.meta.json" "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources/dbip-city-lite.meta.json"
	chmod +x "$(APP_BINARY)"
	$(MAKE) sign-app

sign-app:
	codesign --force --deep -s "$(CODESIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS) "$(BUILD_DIR)/$(APP_NAME).app"

verify-universal:
	lipo -info "$(APP_BINARY)"

dmg:
	hdiutil create -volname "$(APP_NAME)" \
	  -srcfolder "$(BUILD_DIR)/$(APP_NAME).app" \
	  -ov -format UDZO \
	  "$(BUILD_DIR)/$(APP_NAME).dmg"

notarize:
	xcrun notarytool submit "$(BUILD_DIR)/$(APP_NAME).dmg" \
	  --apple-id "$(APPLE_ID)" \
	  --team-id "$(APPLE_TEAM_ID)" \
	  --password "$(APPLE_APP_PASSWORD)" \
	  --wait
	xcrun stapler staple "$(BUILD_DIR)/$(APP_NAME).dmg"

update-db:
	bash scripts/update-dbip.sh

release: build dmg

release-notarized: build dmg notarize
