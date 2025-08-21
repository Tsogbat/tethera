#!/bin/bash

# Foundation Terminal - Build Script
echo "Building Foundation Terminal..."

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: This project requires macOS"
    exit 1
fi

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "Error: Xcode is not installed. Please install Xcode from the App Store."
    exit 1
fi

# Check if Metal is available
if ! system_profiler SPDisplaysDataType | grep -q "Metal"; then
    echo "Warning: Metal may not be available on this system"
fi

# Create build directory
mkdir -p build

# Build the project
echo "Building with Xcode..."
xcodebuild -project Terminal.xcodeproj -scheme Terminal -configuration Debug -derivedDataPath build

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "You can now run the application from Xcode or find it in build/Build/Products/Debug/"
else
    echo "Build failed. Please check the error messages above."
    exit 1
fi
