# Quick Start Guide

## Get Running in 5 Minutes

### Prerequisites Check

```bash
# Check macOS version (needs 14.0+)
sw_vers

# Check Xcode version (needs 15.0+)
xcodebuild -version

# Check Metal support
system_profiler SPDisplaysDataType | grep -i metal
```

### Option 1: Xcode (Recommended)

1. **Open Project**

   ```bash
   open Terminal.xcodeproj
   ```

2. **Select Target**

   - Choose "Terminal" target
   - Select your development team for code signing

3. **Build & Run**
   - Press ⌘+R or click the Play button
   - The terminal window should appear with your shell

### Option 2: Command Line

```bash
# Build the project
make build

# Run the application
make run
```

### Option 3: Swift Package Manager

```bash
# Build with SPM
swift build

# Run the executable
swift run
```

## What You Should See

1. **Black terminal window** opens
2. **Shell prompt** appears (e.g., `%` for zsh)
3. **Type commands** like:
   ```bash
   ls -la
   pwd
   echo "Hello, Terminal!"
   ```

## Troubleshooting

### Build Errors

- **"Metal not supported"**: Your GPU doesn't support Metal
- **"Code signing required"**: Select a development team in Xcode
- **"Permission denied"**: Allow terminal access in System Preferences

### Runtime Issues

- **"No shell found"**: Check your `$SHELL` environment variable
- **"Window not responding"**: Check Console.app for crash logs

## Next Steps

1. **Explore the code**: Start with `TerminalSession.swift`
2. **Modify rendering**: Edit `Shaders.metal` for visual changes
3. **Add features**: Extend `TerminalBuffer.swift` for new functionality

## Need Help?

- Check the full `README.md` for detailed documentation
- Review `demo.md` for feature explanations
- Use `make help` for build options

## Performance Tips

- **Resize window** to see dynamic terminal sizing
- **Type quickly** to test input handling
- **Run complex commands** to test shell integration

The terminal should feel responsive and smooth with 60 FPS rendering!
