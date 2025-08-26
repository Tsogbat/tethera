# Tethera - Makefile

.PHONY: all clean build run app

# Default target
all: build

# Build the project
build:
	@echo "Building Tethera..."
	@swift build

# Build the app bundle
app: build
	@echo "Building Tethera app bundle..."
	@./build_app.sh

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf .build/
	@rm -rf Tethera.app/
	@rm -rf *.icns
	@rm -rf *.iconset/

# Run the application
run: build
	@echo "Running Tethera..."
	@swift run

# Run the app bundle
run-app: app
	@echo "Running Tethera app bundle..."
	@open Tethera.app

# Install dependencies
deps:
	@echo "Installing dependencies..."
	@swift package resolve

# Show project structure
structure:
	@echo "Project Structure:"
	@find Terminal -name "*.swift" -o -name "*.metal" | sort

# Help
help:
	@echo "Available targets:"
	@echo "  build     - Build the project"
	@echo "  app       - Build the app bundle with icon"
	@echo "  clean     - Clean build artifacts"
	@echo "  run       - Build and run the application"
	@echo "  run-app   - Build app bundle and run it"
	@echo "  deps      - Install dependencies"
	@echo "  structure - Show project structure"
	@echo "  help      - Show this help message"
