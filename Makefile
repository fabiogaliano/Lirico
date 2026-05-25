# Build and install Lirico from source.
#
# The built product is "Lirico" (set via PRODUCT_NAME in the Xcode project).
# The Xcode project and scheme files are still named "LyricsX" internally;
# update the vars below if those are ever renamed too.
PROJECT  := LyricsX.xcodeproj
SCHEME   := LyricsX
APP_NAME := Lirico

DERIVED := build
APP     := $(DERIVED)/Build/Products/Release/$(APP_NAME).app
DEST    := /Applications/$(APP_NAME).app

.PHONY: help build install run clean

help:
	@echo "Targets:"
	@echo "  make build     Build the Release app into $(DERIVED)/"
	@echo "  make install   Build, copy to $(DEST), relaunch"
	@echo "  make run       Open the installed app"
	@echo "  make clean     Remove $(DERIVED)/"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration Release -derivedDataPath $(DERIVED) -quiet build

install: build
	-killall $(APP_NAME) 2>/dev/null || true
	rm -rf $(DEST)
	cp -R $(APP) $(DEST)
	open $(DEST)

run:
	open $(DEST)

clean:
	rm -rf $(DERIVED)
