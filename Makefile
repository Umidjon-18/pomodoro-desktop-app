PROJECT = Pomodoro.xcodeproj
SCHEME = Pomodoro
DERIVED = build
DEST = 'platform=macOS,arch=arm64'
APP = $(DERIVED)/Build/Products/Release/Pomodoro.app

.PHONY: project build debug test install run clean icon release

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) -destination $(DEST) -quiet build

debug: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) -destination $(DEST) -quiet build

test: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) -destination $(DEST) -quiet test

install: build
	-osascript -e 'quit app "Pomodoro"'
	rm -rf /Applications/Pomodoro.app
	cp -R $(APP) /Applications/
	open /Applications/Pomodoro.app

run: debug
	open $(DERIVED)/Build/Products/Debug/Pomodoro.app

clean:
	rm -rf $(DERIVED) $(PROJECT)

# Re-render the app icon after editing scripts/make-icon.swift.
icon:
	swift scripts/make-icon.swift Pomodoro/Assets.xcassets/AppIcon.appiconset/icon_1024.png
	for s in 16 32 64 128 256 512; do \
		sips -z $$s $$s Pomodoro/Assets.xcassets/AppIcon.appiconset/icon_1024.png \
			--out Pomodoro/Assets.xcassets/AppIcon.appiconset/icon_$$s.png >/dev/null; \
	done

# Universal, Developer ID-signed, notarized DMG in dist/ (see scripts/release.sh).
release:
	scripts/release.sh
