import AppKit
import SwiftUI

@MainActor
final class AgentConversationWindowController {
    private var window: NSWindow?
    private let viewModel = AgentConversationViewModel()

    private var sendHandler: ((String) -> Void)?
    private var finalizeHandler: (() -> Void)?
    private var injectLastHandler: (() -> Void)?
    private var cancelHandler: (() -> Void)?

    func show(
        targetApp: String,
        onSend: @escaping (String) -> Void,
        onFinalize: @escaping () -> Void,
        onInjectLast: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        sendHandler = onSend
        finalizeHandler = onFinalize
        injectLastHandler = onInjectLast
        cancelHandler = onCancel

        let root = AgentConversationView(
            model: viewModel,
            targetApp: targetApp,
            onSend: { [weak self] text in self?.sendHandler?(text) },
            onFinalize: { [weak self] in self?.finalizeHandler?() },
            onInjectLast: { [weak self] in self?.injectLastHandler?() },
            onCancel: { [weak self] in self?.cancelHandler?() }
        )

        let host = NSHostingView(rootView: root)
        let win: NSWindow
        if let existing = window {
            win = existing
            win.contentView = host
        } else {
            win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Walkietalkie Agent"
            win.isReleasedWhenClosed = false
            win.level = .statusBar
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.contentView = host
            window = win
        }

        positionCenter(win)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
        sendHandler = nil
        finalizeHandler = nil
        injectLastHandler = nil
        cancelHandler = nil
    }

    func replaceMessages(_ messages: [AgentHUDMessage]) {
        viewModel.messages = messages
    }

    func appendMessage(_ message: AgentHUDMessage) {
        viewModel.messages.append(message)
    }

    func setThinking(_ value: Bool) {
        viewModel.isThinking = value
    }

    func setError(_ message: String?) {
        viewModel.errorText = message
    }

    func setStatus(_ message: String?) {
        viewModel.statusText = message
    }

    private func positionCenter(_ win: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = win.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
