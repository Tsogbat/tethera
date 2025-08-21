#!/bin/bash

echo "Launching Foundation Terminal..."
echo "==============================="

# Build first
make build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo ""
    echo "🚀 Launching terminal..."
    
    # Launch the terminal in the background
    ./.build/debug/Terminal &
    
    # Get the process ID
    TERMINAL_PID=$!
    
    # Wait a moment for the app to start
    sleep 1
    
    # Use AppleScript to bring the terminal to front
    osascript -e 'tell application "Terminal" to activate' 2>/dev/null || true
    osascript -e 'tell application "System Events" to set frontmost of process "Terminal" to true' 2>/dev/null || true
    
    echo "✅ Terminal launched!"
    echo ""
    echo "📝 Instructions:"
    echo "1. You should see a black terminal window with green text"
    echo "2. Click anywhere in the terminal window to focus it"
    echo "3. Click in the text input field at the bottom"
    echo "4. Type some text and press Enter"
    echo "5. Your input should appear in the terminal display"
    echo ""
    echo "🔧 If it's still not working:"
    echo "- Try clicking the terminal window in the dock"
    echo "- Use Cmd+Tab to switch to the Terminal app"
    echo "- Make sure no other terminal apps are running"
    
    # Wait for the process to finish
    wait $TERMINAL_PID
else
    echo "❌ Build failed!"
    exit 1
fi
