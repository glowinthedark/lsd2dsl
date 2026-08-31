# Makefile for lsd2dsl — convenience wrapper around CMake.
#
# Run `make` or `make help` to list all available targets.

.DEFAULT_GOAL := help

# Homebrew prefix (/opt/homebrew on Apple Silicon, /usr/local on Intel)
BREW_PREFIX := $(shell brew --prefix 2>/dev/null || echo /usr/local)

# Build configuration (override on the command line, e.g. `make build ENABLE_DUDEN=OFF`)
BUILD_DIR   ?= build
BUILD_TYPE  ?= RelWithDebInfo
ENABLE_DUDEN ?= ON
JOBS        ?= $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# Qt and the other dependencies are keg-only / non-standard prefixes on macOS
CMAKE_PREFIX_PATH := $(BREW_PREFIX)/opt/qt;$(BREW_PREFIX)/opt/qtwebengine;$(BREW_PREFIX)
CONFIGURE := cmake -S . -B $(BUILD_DIR) \
	-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
	-DENABLE_DUDEN=$(ENABLE_DUDEN) \
	-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
	-DCMAKE_PREFIX_PATH="$(CMAKE_PREFIX_PATH)"

BINARY := $(BUILD_DIR)/app/lsd2dsl

.PHONY: help deps configure build test run clean distclean rebuild

help: ## Show this help (auto-generated from target comments)
	@echo "lsd2dsl build system"
	@echo ""
	@echo "Usage: make <target> [VAR=value ...]"
	@echo ""
	@echo "Common variables:"
	@echo "  BUILD_DIR=$(BUILD_DIR)  BUILD_TYPE=$(BUILD_TYPE)  ENABLE_DUDEN=$(ENABLE_DUDEN)  JOBS=$(JOBS)"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_.-]+:.*## / {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Examples:"
	@echo "  make deps build test            # full from-scratch build with tests"
	@echo "  make build ENABLE_DUDEN=OFF     # build without QtWebEngine/Duden support"

deps: ## Install build dependencies via Homebrew (macOS)
	brew install cmake boost qt qtwebengine fmt libsndfile libvorbis libogg
	@echo "Note: GoogleTest is fetched automatically by CMake if not installed."

configure: ## Configure the CMake build tree
	$(CONFIGURE)

build: configure ## Compile all libraries, the app and the tests
	cmake --build $(BUILD_DIR) -j$(JOBS)

test: build ## Build and run the test suite via ctest
	cd $(BUILD_DIR) && ctest --output-on-failure

run: build ## Build and print the lsd2dsl command-line usage
	$(BINARY) --help

clean: ## Remove build artifacts but keep the CMake configuration
	cmake --build $(BUILD_DIR) --target clean 2>/dev/null || true

distclean: ## Remove the entire build tree
	rm -rf $(BUILD_DIR)

rebuild: distclean build ## Wipe the build tree and rebuild from scratch
