#!/bin/bash

echo "Testing Foundation Terminal..."
echo "=============================="

# Build the project
echo "Building project..."
make build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo ""
    echo "To run the terminal:"
    echo "1. Run: make run"
    echo "2. Or run directly: ./.build/debug/Terminal"
    echo ""
    echo "You should see:"
    echo "- A black terminal window"
    echo "- Green text saying 'Foundation Terminal - Ready!'"
    echo "- A '$ ' prompt"
    echo "- Ability to type and see your input"
    echo ""
    echo "If it's still not working, try:"
    echo "- Click inside the terminal window to focus it"
    echo "- Press any key to see if input is working"
    echo "- Check Console.app for any error messages"
else
    echo "❌ Build failed!"
    exit 1
fi
