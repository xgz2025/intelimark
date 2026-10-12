# Nextmark developer tasks. The Xcode project is generated from project.yml.
PROJECT = Nextmark.xcodeproj

.PHONY: bootstrap generate open test build-ios build-macos clean

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen

generate: bootstrap
	xcodegen generate
	@# The app targets' build checks this is newer than project.yml.
	touch $(PROJECT)/project.pbxproj

open: generate
	open $(PROJECT)

test:
	swift test --package-path Packages/NextmarkKit

build-ios: generate
	xcodebuild build -project $(PROJECT) -scheme Nextmark-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO

build-macos: generate
	xcodebuild build -project $(PROJECT) -scheme Nextmark-macOS -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO

clean:
	rm -rf $(PROJECT) Packages/NextmarkKit/.build
