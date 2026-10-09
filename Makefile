# Ainkrad — common developer tasks.
#
# The Xcode project is generated from project.yml by XcodeGen and is NOT
# committed. After cloning, run `make` (or `make open`) to generate it.
# project.yml is the source of truth — re-run `make generate` after editing it.

# The project needs the macOS 27 SDK; default to Xcode 27 at /Applications/Xcode.app when
# it's installed. Override on the command line: `make build DEVELOPER_DIR=…`.
ifneq ($(wildcard /Applications/Xcode.app),)
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
endif

SCHEME := Ainkrad
PROJECT := Ainkrad.xcodeproj

.DEFAULT_GOAL := generate
.PHONY: generate open build test validate-themes release clean help sample devhost

# The sideload directory is `<cacheRoot>/DevPlugins`, and cacheRoot is
# `~/Library/Application Support/<bundle-id>/Cache` (see AinkradHome.defaultCacheRoot
# and AppEnvironment+BootstrapStores). It is deliberately NOT under the user's
# Ainkrad Home: dev plugin bundles are rebuildable machine state, not vault data.
DEV_PLUGINS := $(HOME)/Library/Application Support/com.ainkrad.app/Cache/DevPlugins

generate: ## Generate the Xcode project from project.yml
	xcodegen generate

open: generate ## Generate the project and open it in Xcode
	open $(PROJECT)

# `-derivedDataPath build`, matching `devhost` and `test`.
#
# Without it this target alone wrote to Xcode's default DerivedData while every
# other target in this repo — and every script and sibling repo that looks for
# a built app — reads ./build. The visible symptom is that `make build`
# succeeds and `./build/.../Ainkrad.app` stays whatever it was: during M9 that
# was a three-week-old binary that failed to launch with a dyld symbol error,
# and the build kept "succeeding".
build: lint generate ## Build the app (Debug)
	xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath build -destination 'platform=macOS' build

test: lint generate ## Run the test suite
	xcodebuild -scheme $(SCHEME) -destination 'platform=macOS' test

# The full suite with real theme files: ThemeDirectoryValidationTests reads AINKRAD_THEMES_DIR
# (xcodebuild hands TEST_RUNNER_-prefixed variables to the test process). Without THEMES
# that test prints a loud SKIPPED and passes, so plain `make test` checks no theme files.
validate-themes: lint generate ## Run the test suite validating THEMES=<dir> (e.g. ../AinkradCatalog/themes)
	@test -n "$(THEMES)" || { echo "validate-themes: THEMES is required, e.g. make validate-themes THEMES=../AinkradCatalog/themes"; exit 2; }
	@test -d "$(THEMES)" || { echo "validate-themes: $(THEMES) is not a directory"; exit 2; }
	TEST_RUNNER_AINKRAD_THEMES_DIR="$(abspath $(THEMES))" xcodebuild -scheme $(SCHEME) -destination 'platform=macOS' test

release: ## Build a distributable .dmg (see scripts/release.sh)
	./scripts/release.sh

clean: ## Remove the generated project and build output
	rm -rf $(PROJECT) dist

devhost: generate ## Build the AinkradDevHost app (Debug)
	xcodebuild -scheme AinkradDevHost -configuration Debug -derivedDataPath build \
		-destination 'platform=macOS' build
	@echo "Built → build/Build/Products/Debug/AinkradDevHost.app"

sample: generate ## Build the Hello sample plugin and sideload it into DevPlugins
	xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath build \
		-destination 'platform=macOS' build
	mkdir -p "$(DEV_PLUGINS)"
	rm -rf "$(DEV_PLUGINS)/HelloPlugin.bundle"
	cp -R build/Build/Products/Debug/HelloPlugin.bundle "$(DEV_PLUGINS)/HelloPlugin.bundle"
	@echo "Sideloaded HelloPlugin.bundle → $(DEV_PLUGINS)"

help: ## List the available targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-10s %s\n", $$1, $$2}'

include scripts/guardrails.mk
