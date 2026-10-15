import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        sharingType = .none
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func concealFromCapture() {
        sharingType = .none
    }
}

final class DragHostingView<Content: View>: NSHostingView<Content> {
    var onMoved: ((NSPoint) -> Void)?
    private var grab = NSPoint.zero
    private var suppressDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        grab = event.locationInWindow
        let local = convert(event.locationInWindow, from: nil)
        let hit = hitTest(local)
        let name = hit.map { String(describing: type(of: $0)) } ?? ""
        suppressDrag = hit is NSTextView || hit is NSTextField || name.contains("Text")
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if suppressDrag {
            super.mouseDragged(with: event)
            return
        }
        let mouse = NSEvent.mouseLocation
        onMoved?(NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }
}

final class IslandPanelController {
    let state: IslandState
    let panel: IslandPanel
    private var center = NSPoint.zero
    private var mouseTimer: Timer?

    init(state: IslandState) {
        self.state = state
        let panel = IslandPanel()
        let host = DragHostingView(rootView: IslandView(state: state))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            host.safeAreaRegions = []
        }
        panel.contentView = host
        self.panel = panel
        host.onMoved = { [weak self] origin in
            self?.move(to: origin)
        }

        state.onShow = { [weak self] point in
            guard let self else { return }
            self.center = point
            self.syncFrame()
            self.panel.concealFromCapture()
            self.panel.orderFrontRegardless()
        }
        state.onHide = { [weak self] in
            self?.panel.ignoresMouseEvents = true
            self?.panel.orderOut(nil)
        }
        state.onLayout = { [weak self] in
            self?.updatePassthrough()
        }
        startMouseTracking()
    }

    func focusForTyping() {
        panel.concealFromCapture()
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func move(to origin: NSPoint) {
        let clamped = clamp(origin, size: panel.frame.size)
        panel.setFrameOrigin(clamped)
        center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
    }

    private func syncFrame() {
        let size = IslandMetrics.canvas
        var origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        origin = clamp(origin, size: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
    }

    private func clamp(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let probe = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { NSMouseInRect(probe, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return origin }
        let vis = screen.visibleFrame
        let x = min(max(origin.x, vis.minX + 6), max(vis.minX + 6, vis.maxX - size.width - 6))
        let y = min(max(origin.y, vis.minY + 6), max(vis.minY + 6, vis.maxY - size.height - 6))
        return NSPoint(x: x, y: y)
    }

    private func startMouseTracking() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updatePassthrough()
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func updatePassthrough() {
        guard panel.isVisible, let content = panel.contentView else { return }
        let mouse = NSEvent.mouseLocation
        let local = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        let hit = state.islandRect(in: content.bounds).insetBy(dx: -8, dy: -8)
        let inside = hit.contains(local)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
    }
}
