import AppKit
import SwiftUI

@MainActor
final class HUDWindowController {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var cancelHandler: (() -> Void)?

    func show(status: String, targetApp: String, onCancel: @escaping () -> Void) {
        cancelHandler = onCancel

        let root = HUDView(targetApp: targetApp, status: status) { [weak self] in
            self?.cancelHandler?()
        }

        let host = NSHostingView(rootView: root)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = host
        } else {
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                styleMask: [.nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.contentView = host
            self.panel = panel
        }

        positionTopCenter(panel)
        panel.orderFrontRegardless()
        installEscMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        removeEscMonitor()
        cancelHandler = nil
    }

    private func installEscMonitor() {
        removeEscMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelHandler?()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    private func positionTopCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = window.frame.size
        let x = frame.midX - (size.width / 2)
        let y = frame.maxY - size.height - 28
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
