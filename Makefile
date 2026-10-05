# Build and install Lirico from source.
#
# The built product is "Lirico" (set via PRODUCT_NAME in the Xcode project).
#
# Builds default to the Debug configuration: it skips whole-module
# optimization, so a one-file change rebuilds in ~20s instead of ~85s, and it
# fans compilation out across all cores. Use the `release` targets only when
# producing an optimized build to distribute. Debug and Release products live
# in separate subfolders of the same DERIVED dir, so the two configurations
# keep independent caches and never force each other to rebuild.
PROJECT  := Lirico.xcodeproj
SCHEME   := Lirico

# The product name is configuration-specific: Debug builds to "Lirico-Debug"
# (bundle id dev.fabiogaliano.Lirico) so a dev build installs and runs
# side-by-side with the real "Lirico" Release app without conflict.
APP_NAME       := Lirico
APP_NAME_Debug := Lirico-Debug

# .noindex keeps Spotlight from listing the built .app copies in app launchers.
DERIVED := build.noindex
CONFIG  ?= Debug
# CFBundleVersion. The offset continues the build numbers LyricsX bumped in
# place (last: 2947), so they keep increasing. Passed as a build setting so
# Info.plist processing bakes it in before signing; Xcode IDE builds fall back
# to the project's CURRENT_PROJECT_VERSION (0).
BUILD_NUMBER := $(shell echo $$(( $$(git rev-list --count HEAD) + 1304 )))

PRODUCT := $(if $(APP_NAME_$(CONFIG)),$(APP_NAME_$(CONFIG)),$(APP_NAME))
APP     := $(DERIVED)/Build/Products/$(CONFIG)/$(PRODUCT).app
DEST    := /Applications/$(PRODUCT).app
DMG     := $(DERIVED)/$(PRODUCT).dmg
ZIP     := $(DERIVED)/$(PRODUCT).zip

.PHONY: help build release install install-release dmg zip package run clean

help:
	@echo "Targets:"
	@echo "  make build            Build (Debug) into $(DERIVED)/ — fast dev loop"
	@echo "  make release          Build (Release, optimized) — for distribution"
	@echo "  make install          Build (Debug), copy to $(DEST), relaunch"
	@echo "  make install-release  Build (Release), copy to $(DEST), relaunch"
	@echo "  make dmg              Package Release into $(DMG)"
	@echo "  make zip              Package Release into $(ZIP)"
	@echo "  make package          Create both .dmg and .zip in $(DERIVED)/"
	@echo "  make run              Open the installed app"
	@echo "  make clean            Remove $(DERIVED)/"
	@echo ""
	@echo "Override the configuration on any target with CONFIG=Release."

# Lirico is ad-hoc signed (CODE_SIGN_IDENTITY = "-") and unsandboxed, so it
# embeds no provisioning profile and needs no Apple account: builds require
# neither a signing identity nor -allowProvisioningUpdates, and the installed
# app never expires.
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration $(CONFIG) -derivedDataPath $(DERIVED) \
	  CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) -quiet build

release:
	$(MAKE) build CONFIG=Release

install: build
	-killall $(PRODUCT) 2>/dev/null || true
	@i=0; while pgrep -x $(PRODUCT) >/dev/null 2>&1 && [ $$i -lt 50 ]; do sleep 0.1; i=$$((i+1)); done
	-killall -9 $(PRODUCT) 2>/dev/null || true
	rm -rf $(DEST)
	cp -R $(APP) $(DEST)
	open $(DEST)

install-release:
	$(MAKE) install CONFIG=Release

dmg:
	$(MAKE) build-dmg CONFIG=Release

build-dmg: build
	@rm -rf $(DERIVED)/dmg-staging $(DMG)
	@mkdir -p $(DERIVED)/dmg-staging
	cp -R $(APP) $(DERIVED)/dmg-staging/
	ln -s /Applications $(DERIVED)/dmg-staging/Applications
	hdiutil create -volname "$(PRODUCT)" -srcfolder $(DERIVED)/dmg-staging -ov -format UDZO $(DMG)
	@rm -rf $(DERIVED)/dmg-staging

zip:
	$(MAKE) build-zip CONFIG=Release

build-zip: build
	@rm -f $(ZIP)
	ditto -c -k --sequesterRsrc --keepParent $(APP) $(ZIP)

package:
	$(MAKE) build-package CONFIG=Release

build-package: build-dmg build-zip

run:
	open $(DEST)

clean:
	rm -rf $(DERIVED)
