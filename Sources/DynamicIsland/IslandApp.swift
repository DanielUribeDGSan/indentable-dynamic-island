import AppKit
import Darwin
import SwiftUI

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let state = IslandState()
    private var panelController: IslandPanelController?
    private var hotkey: HotkeyMonitor?
    private var selection: SelectionMonitor?
    private var statusItem: NSStatusItem?
    private var instanceLockFD: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireInstanceLock() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.global(qos: .userInitiated).async {
            warmLiquidOrb()
        }
        let panelController = IslandPanelController(state: state)
        panelController.panel.concealFromCapture()
        self.panelController = panelController
        state.onFocus = { [weak panelController] in
            panelController?.focusForTyping()
        }

        let hotkey = HotkeyMonitor(onTrigger: { [weak self] in
            self?.state.toggleAtPointer()
        }, shouldIgnore: { [weak self] in
            guard let self else { return true }
            return self.state.isPresented && self.state.phase == .settings
        })
        self.hotkey = hotkey

        let selection = SelectionMonitor(state: state)
        selection.onTrustChanged = { trusted in
            if trusted { hotkey.start() }
        }
        selection.start()
        selection.promptForTrust()
        hotkey.start()
        self.selection = selection

        installStatusItem()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.state.isPresented, self.state.phase == .settings else {
                return event
            }
            self.state.closeSettings()
            return nil
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        hotkey?.start()
    }

    private func acquireInstanceLock() -> Bool {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("instance.lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        instanceLockFD = fd
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Dynamic Island")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Dynamic Island"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Abrir isla", action: #selector(openIsland)))
        menu.addItem(item("Configuración", action: #selector(openSettings)))
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Tres veces ⌘: isla junto al puntero", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        let drag = NSMenuItem(title: "Arrástrala para moverla", action: nil, keyEquivalent: "")
        drag.isEnabled = false
        menu.addItem(drag)
        let privacy = NSMenuItem(title: "Invisible en capturas y al compartir", action: nil, keyEquivalent: "")
        privacy.isEnabled = false
        menu.addItem(privacy)
        let engine = NSMenuItem(title: RustCore.version, action: nil, keyEquivalent: "")
        engine.isEnabled = false
        menu.addItem(engine)
        menu.addItem(.separator())
        if state.accessibilityTrusted {
            let trusted = NSMenuItem(title: "Accesibilidad concedida", action: nil, keyEquivalent: "")
            trusted.isEnabled = false
            menu.addItem(trusted)
        } else {
            menu.addItem(item("Activar Accesibilidad…", action: #selector(openAccessibility)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Salir", action: #selector(quit)))
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openIsland() {
        state.presentAtPointer(phase: .live)
    }

    @objc private func openSettings() {
        state.presentAtPointer(phase: .settings)
    }

    @objc private func openAccessibility() {
        selection?.promptForTrust()
        SelectionMonitor.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
