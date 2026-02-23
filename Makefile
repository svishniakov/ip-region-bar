BUILD_DIR    = build
APP_NAME     = IPRegionBar
BUNDLE_ID    = com.yourname.ipregionbar
VERSION      = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
               IPRegionBar/App/Info.plist)

.PHONY: build dmg notarize release

build:
	swift build -c release
	rm -rf "$(BUILD_DIR)/$(APP_NAME).app"
	mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS"
	cp ".build/release/$(APP_NAME)" "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)"
	cp "IPRegionBar/App/Info.plist" "$(BUILD_DIR)/$(APP_NAME).app/Contents/Info.plist"
	chmod +x "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)"
	codesign --force --deep -s - "$(BUILD_DIR)/$(APP_NAME).app"

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

release: build dmg notarize
