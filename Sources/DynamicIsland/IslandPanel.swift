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

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

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
        let size = panel.frame.size
        place(center: NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2))
    }

    private func syncFrame() {
        place(center: center)
    }

    private func place(center desired: NSPoint) {
        let size = IslandMetrics.canvas
        let next = clampIslandCenter(desired)
        center = next
        let origin = NSPoint(x: next.x - size.width / 2, y: next.y - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
    }

    private func clampIslandCenter(_ point: NSPoint) -> NSPoint {
        let island = state.layout.size
        let margin: CGFloat = 4
        let regions = NSScreen.screens.map { screen -> NSRect in
            let frame = screen.frame
            let insetX = min(island.width / 2 + margin, frame.width / 2)
            let insetY = min(island.height / 2 + margin, frame.height / 2)
            return NSRect(
                x: frame.minX + insetX,
                y: frame.minY + insetY,
                width: max(0, frame.width - insetX * 2),
                height: max(0, frame.height - insetY * 2)
            )
        }
        guard !regions.isEmpty else { return point }
        if regions.contains(where: { $0.contains(point) }) {
            return point
        }
        var best = point
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for region in regions {
            let x = min(max(point.x, region.minX), region.maxX)
            let y = min(max(point.y, region.minY), region.maxY)
            let distance = (x - point.x) * (x - point.x) + (y - point.y) * (y - point.y)
            if distance < bestDistance {
                bestDistance = distance
                best = NSPoint(x: x, y: y)
            }
        }
        return best
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
