# Foundation Terminal - Makefile

.PHONY: all clean build run

# Default target
all: build

# Build the project
build:
	@echo "Building Foundation Terminal..."
	@swift build

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf .build/

# Run the application (if built)
run: build
	@echo "Running Terminal..."
	@if [ -f ".build/debug/Terminal" ]; then \
		./.build/debug/Terminal; \
	else \
		echo "No built executable found. Run 'make build' first."; \
	fi

# Install dependencies (if using SPM)
deps:
	@echo "Installing dependencies..."
	@swift package resolve

# Show project structure
structure:
	@echo "Project Structure:"
	@echo "Terminal/"
	@find Terminal -name "*.swift" -o -name "*.metal" -o -name "*.plist" | sort

# Help
help:
	@echo "Available targets:"
	@echo "  build     - Build the project"
	@echo "  clean     - Clean build artifacts"
	@echo "  run       - Build and run the application"
	@echo "  deps      - Install dependencies"
	@echo "  structure - Show project structure"
	@echo "  help      - Show this help message"
