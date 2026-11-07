import AppKit
import SceneKit
import SwiftUI

/// What the little computer's screen shows.
enum RetroScreenState: Equatable {
    case prompt
    case count(Int, String)

    var image: NSImage {
        switch self {
        case .prompt: return RetroScreen.prompt()
        case .count(let value, let caption): return RetroScreen.count(value, caption: caption)
        }
    }
}

/// The 3D computer, for Home and About. It renders only while it's on screen in the key
/// window: hidden or in the background it costs nothing.
struct RetroComputerView: NSViewRepresentable {
    var screen: RetroScreenState = .prompt
    var dark: Bool
    var showsKeyboard = true
    /// Called with a key's name (`esc`, `⌘`, `K`, `D`, `t`, `return`) after it's pressed.
    var onKey: ((String) -> Void)?

    func makeNSView(context: Context) -> RetroSceneView {
        RetroSceneView(dark: dark, keyboard: showsKeyboard)
    }

    func updateNSView(_ view: RetroSceneView, context: Context) {
        view.onKey = onKey
        view.show(screen)
    }

    static func dismantleNSView(_ view: RetroSceneView, coordinator: ()) {
        view.stop()
    }
}

final class RetroSceneView: SCNView {
    let model: RetroComputer
    var onKey: ((String) -> Void)?
    private var shown: RetroScreenState?
    private var observers: [NSObjectProtocol] = []
    private var tracking: NSTrackingArea?

    init(dark: Bool, keyboard: Bool) {
        model = RetroComputer(keyboard: keyboard)
        super.init(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        model.addStudio(dark: dark)
        model.scene.background.contents = NSColor.clear
        pointOfView = keyboard
            ? model.addCamera(at: SCNVector3(5.2, 3.9, 11.6), lookingAt: SCNVector3(0.35, 0.95, 1.5), fov: 28)
            : model.addCamera(at: SCNVector3(3.4, 3.0, 8.6), lookingAt: SCNVector3(0.1, 1.4, 0.2), fov: 27)
        scene = model.scene
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        rendersContinuously = false
        allowsCameraControl = false
        // The idle float is slow: 30 fps is plenty. Interaction gets 60 for a moment.
        preferredFramesPerSecond = 30
    }

    private var smoothUntil = Date.distantPast

    private func smoothForAMoment() {
        smoothUntil = Date().addingTimeInterval(1.2)
        guard preferredFramesPerSecond != 60 else { return }
        preferredFramesPerSecond = 60
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self, Date() >= self.smoothUntil else { return }
            self.preferredFramesPerSecond = 30
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ state: RetroScreenState) {
        guard state != shown else { return }
        shown = state
        model.setScreen(state.image)
    }

    /// A slow float and sway when it comes into view, then rest: a terminal can sit on Home
    /// for hours, and a still frame costs nothing. Low Power Mode skips it.
    private func floatOnce() {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled, model.computer.action(forKey: "idle") == nil else { return }
        let up = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 2.6)
        up.timingMode = .easeInEaseOut
        let sway = SCNAction.rotateBy(x: 0, y: 0.05, z: 0, duration: 2.6)
        sway.timingMode = .easeInEaseOut
        let cycle = SCNAction.sequence([.group([up, sway]), .group([up.reversed(), sway.reversed()])])
        model.computer.runAction(.repeat(cycle, count: 2), forKey: "idle")
    }

    // MARK: Only render while visible

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return updatePlaying() }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePlaying() }
            })
        }
        updatePlaying()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updatePlaying()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updatePlaying()
    }

    private func updatePlaying() {
        let visible = window.map { $0.isKeyWindow && $0.occlusionState.contains(.visible) } ?? false
        let playing = visible && !isHiddenOrHasHiddenAncestor
        if playing && !isPlaying { floatOnce() }
        model.scene.isPaused = !playing
        isPlaying = playing
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        model.scene.isPaused = true
        isPlaying = false
    }

    // MARK: Hover tilt and keys

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let x = (point.x / max(bounds.width, 1)) - 0.5
        let y = (point.y / max(bounds.height, 1)) - 0.5
        smoothForAMoment()
        tilt(yaw: x * 0.32, pitch: -y * 0.12)
        (key(at: point) != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func mouseExited(with event: NSEvent) {
        tilt(yaw: 0, pitch: 0)
        NSCursor.arrow.set()
    }

    private func tilt(yaw: CGFloat, pitch: CGFloat) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.7
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
        model.rig.eulerAngles = SCNVector3(pitch, yaw, 0)
        SCNTransaction.commit()
    }

    private func key(at point: CGPoint) -> String? {
        hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            .lazy.compactMap { self.model.keyName(for: $0.node) }.first
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let name = key(at: point) else { return super.mouseDown(with: event) }
        smoothForAMoment()
        model.press(name)
        let callback = onKey
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { callback?(name) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
