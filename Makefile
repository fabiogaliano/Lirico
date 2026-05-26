# Build and install Lirico from source.
#
# The built product is "Lirico" (set via PRODUCT_NAME in the Xcode project).
# The Xcode project and scheme files are still named "LyricsX" internally;
# update the vars below if those are ever renamed too.
#
# Builds default to the Debug configuration: it skips whole-module
# optimization, so a one-file change rebuilds in ~20s instead of ~85s, and it
# fans compilation out across all cores. Use the `release` targets only when
# producing an optimized build to distribute. Debug and Release products live
# in separate subfolders of the same DERIVED dir, so the two configurations
# keep independent caches and never force each other to rebuild.
PROJECT  := LyricsX.xcodeproj
SCHEME   := LyricsX

# The product name is configuration-specific: Debug builds to "Lirico-Debug"
# (bundle id dev.fabiogaliano.LyricsX) so a dev build installs and runs
# side-by-side with the real "Lirico" Release app without conflict.
APP_NAME       := Lirico
APP_NAME_Debug := Lirico-Debug

DERIVED := build
CONFIG  ?= Debug
PRODUCT := $(if $(APP_NAME_$(CONFIG)),$(APP_NAME_$(CONFIG)),$(APP_NAME))
APP     := $(DERIVED)/Build/Products/$(CONFIG)/$(PRODUCT).app
DEST    := /Applications/$(PRODUCT).app

.PHONY: help build release install install-release run clean

help:
	@echo "Targets:"
	@echo "  make build            Build (Debug) into $(DERIVED)/ — fast dev loop"
	@echo "  make release          Build (Release, optimized) — for distribution"
	@echo "  make install          Build (Debug), copy to $(DEST), relaunch"
	@echo "  make install-release  Build (Release), copy to $(DEST), relaunch"
	@echo "  make run              Open the installed app"
	@echo "  make clean            Remove $(DERIVED)/"
	@echo ""
	@echo "Override the configuration on any target with CONFIG=Release."

# -allowProvisioningUpdates lets xcodebuild create/refresh the managed
# development provisioning profile (Xcode.app does this implicitly; xcodebuild
# does not). Required because the app's entitlements (App Groups, keychain
# access groups) only resolve through a real signed profile.
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration $(CONFIG) -derivedDataPath $(DERIVED) \
	  -allowProvisioningUpdates -quiet build

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

run:
	open $(DEST)

clean:
	rm -rf $(DERIVED)
