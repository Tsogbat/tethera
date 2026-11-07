# Tethera - Makefile

.PHONY: all clean build run app dmg test

# Default target
all: build

# Build the project
build:
	@echo "Building Tethera..."
	@swift build

# Build dist/Tethera.app and dist/Tethera-macOS.dmg (universal; UNIVERSAL=0 for this Mac only)
app:
	@scripts/package.sh $(VERSION)

dmg: app

# Run the unit and real-shell tests
test:
	@swift test

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf .build/
	@rm -rf Tethera.app/ dist/
	@rm -rf *.icns
	@rm -rf *.iconset/
	@rm -rf releases/

# Run the application
run: build
	@echo "Running Tethera..."
	@swift run

# Run the app bundle
run-app: app
	@open dist/Tethera.app

# Install dependencies
deps:
	@echo "Installing dependencies..."
	@swift package resolve

# Show project structure
structure:
	@echo "Project Structure:"
	@find Tethera -name "*.swift" | sort

# Help
help:
	@echo "Available targets:"
	@echo "  build     - Build the project"
	@echo "  app / dmg - Build dist/Tethera.app and dist/Tethera-macOS.dmg"
	@echo "  test      - Run the test suite"
	@echo "  clean     - Clean build artifacts"
	@echo "  run       - Build and run the application"
	@echo "  run-app   - Build app bundle and run it"
	@echo "  deps      - Install dependencies"
	@echo "  structure - Show project structure"
	@echo "  help      - Show this help message"
