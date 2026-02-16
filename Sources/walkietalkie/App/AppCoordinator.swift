import AppKit
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: WalkieState = .idle

    private let configStore = ConfigStore()
    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private let detector = TargetAppDetector()
    private let injector = TextInjector()
    private let hud = HUDWindowController()
    private let logger = EventLogger.shared

    private var config: WalkieConfig = .default
    private var sttProvider: STTProvider = MockSTTProvider()
    private var llmProvider: LLMProvider = MockLLMProvider()
    private var isCanceled = false
    private var sessionTargetApp: TargetApp?

    func start() {
        Task {
            do {
                await logger.log("app.start")
                _ = AccessibilityService.isTrusted(promptIfNeeded: true)
                try await reloadConfigAndBindings()
                await logger.log("app.start.ready")
            } catch {
                await logger.log("app.start.error", fields: ["error": error.localizedDescription])
                transition(.error(error.localizedDescription))
            }
        }
    }

    func reloadConfig() {
        Task {
            do {
                await logger.log("config.reload.begin")
                try await reloadConfigAndBindings()
                await logger.log("config.reload.success")
                transition(.done)
                resetToIdleSoon()
            } catch {
                await logger.log("config.reload.error", fields: ["error": error.localizedDescription])
                transition(.error(error.localizedDescription))
            }
        }
    }

    func openConfigInFinder() {
        Task {
            do {
                try await configStore.revealInFinder()
            } catch {
                transition(.error(error.localizedDescription))
            }
        }
    }

    func openLogsInFinder() {
        Task {
            do {
                try await logger.revealInFinder()
            } catch {
                transition(.error(error.localizedDescription))
            }
        }
    }

    func cancelCurrentFlow() {
        Task { await logger.log("flow.canceled") }
        isCanceled = true
        sessionTargetApp = nil
        Task {
            await audioRecorder.cancelAndDiscard()
        }
        hud.hide()
        transition(.idle)
    }

    private func reloadConfigAndBindings() async throws {
        let config = try await configStore.load()
        let stt = try STTFactory.make(config: config.stt)
        let llm = try LLMFactory.make(config: config.llm)
        await logger.log("config.loaded", fields: [
            "stt_provider": config.stt.provider,
            "llm_provider": config.llm.provider
        ])

        self.config = config
        self.sttProvider = stt
        self.llmProvider = llm

        try hotkeyManager.register(config: config) { [weak self] mode, phase in
            Task { @MainActor [weak self] in
                self?.handleHotkey(mode: mode, phase: phase)
            }
        }
    }

    private func handleHotkey(mode: WalkieMode, phase: HotkeyPhase) {
        switch phase {
        case .pressed:
            Task { await logger.log("hotkey.pressed", fields: ["mode": mode.rawValue]) }
            isCanceled = false
            sessionTargetApp = detector.currentTargetApp()
            Task { await logger.log("target.captured", fields: ["app": sessionTargetApp?.name ?? "unknown", "bundle": sessionTargetApp?.bundleID ?? "unknown"]) }
            hud.show(status: "Listening (hold key)", targetApp: currentTargetName()) { [weak self] in
                self?.cancelCurrentFlow()
            }
            transition(.listening(mode))
            Task {
                do {
                    try await audioRecorder.start()
                    await logger.log("recording.started", fields: ["mode": mode.rawValue])
                } catch {
                    await logger.log("recording.start.error", fields: ["mode": mode.rawValue, "error": error.localizedDescription])
                    await MainActor.run {
                        self.hud.show(status: "Error: \(error.localizedDescription)", targetApp: self.currentTargetName()) { [weak self] in
                            self?.cancelCurrentFlow()
                        }
                        self.transition(.error(error.localizedDescription))
                        self.resetToIdleSoon()
                    }
                }
            }

        case .released:
            Task { await logger.log("hotkey.released", fields: ["mode": mode.rawValue]) }
            Task {
                do {
                    let audioURL = try await audioRecorder.stop()
                    await logger.log("recording.stopped", fields: ["mode": mode.rawValue, "path": audioURL.path])
                    try await processRecording(url: audioURL, mode: mode)
                } catch {
                    await logger.log("flow.error", fields: ["mode": mode.rawValue, "error": error.localizedDescription])
                    await MainActor.run {
                        if (error as? WalkieError) == .nothingRecorded {
                            self.hud.hide()
                            self.transition(.idle)
                        } else {
                            self.hud.show(status: "Error: \(error.localizedDescription)", targetApp: self.currentTargetName()) { [weak self] in
                                self?.cancelCurrentFlow()
                            }
                            self.transition(.error(error.localizedDescription))
                            self.resetToIdleSoon()
                        }
                    }
                }
            }
        }
    }

    private func processRecording(url: URL, mode: WalkieMode) async throws {
        if isCanceled { throw WalkieError.canceled }
        await MainActor.run {
            self.transition(.transcribing(mode))
            self.hud.show(status: "Transcribing", targetApp: self.currentTargetName()) { [weak self] in
                self?.cancelCurrentFlow()
            }
        }

        let transcript = try await sttProvider.transcribe(audioURL: url)
        await logger.log("stt.success", fields: ["mode": mode.rawValue, "transcript_chars": "\(transcript.count)"])
        try? FileManager.default.removeItem(at: url)

        if isCanceled { throw WalkieError.canceled }
        let textToInject: String
        switch mode {
        case .dictation:
            textToInject = transcript

        case .agent:
            await MainActor.run {
                self.transition(.agentConversation)
                self.hud.show(status: "Agent partner reasoning", targetApp: self.currentTargetName()) { [weak self] in
                    self?.cancelCurrentFlow()
                }
            }
            let partnerOutput = try await llmProvider.partnerConversation(transcribedRequest: transcript)
            await logger.log("agent.partner.success", fields: ["chars": "\(partnerOutput.count)"])

            if isCanceled { throw WalkieError.canceled }
            await MainActor.run {
                self.transition(.condensing)
                self.hud.show(status: "Condensing final coding prompt", targetApp: self.currentTargetName()) { [weak self] in
                    self?.cancelCurrentFlow()
                }
            }
            textToInject = try await llmProvider.condensePrompt(transcribedRequest: transcript, partnerOutput: partnerOutput)
            await logger.log("agent.condense.success", fields: ["chars": "\(textToInject.count)"])
        }

        if isCanceled { throw WalkieError.canceled }
        try await preInjectAndSend(text: textToInject, mode: mode)
    }

    private func preInjectAndSend(text: String, mode: WalkieMode) async throws {
        let initialTarget = sessionTargetApp ?? detector.currentTargetApp()
        let decision = detector.currentDecision(config: config, targetApp: initialTarget)
        await logger.log("inject.target.check", fields: [
            "app": decision.app.name,
            "bundle": decision.app.bundleID,
            "allowed": decision.allowed ? "true" : "false"
        ])
        guard decision.allowed else {
            throw WalkieError.injectionBlocked(decision.reasonIfBlocked ?? "Target blocked")
        }

        await MainActor.run {
            self.transition(.injecting(decision.app.name))
            self.hud.show(
                status: "Inject into \(decision.app.name)? Esc to cancel",
                targetApp: "\(decision.app.name) (\(decision.app.bundleID))"
            ) { [weak self] in
                self?.cancelCurrentFlow()
            }
        }

        try await Task.sleep(nanoseconds: UInt64(config.injection.preInjectHUDMillis) * 1_000_000)
        if isCanceled { throw WalkieError.canceled }

        await reactivateTargetApp(decision.app)
        try await Task.sleep(nanoseconds: 130_000_000)

        let autoEnter = (mode == .dictation) ? config.modeBehavior.dictation.autoEnter : config.modeBehavior.agent.autoEnter
        try injector.inject(
            text: text,
            pressEnter: autoEnter,
            fallbackToTyping: config.injection.fallbackToKeystrokesOnFailure
        )
        await logger.log("inject.success", fields: [
            "mode": mode.rawValue,
            "chars": "\(text.count)",
            "auto_enter": autoEnter ? "true" : "false"
        ])

        await MainActor.run {
            self.hud.hide()
            self.transition(.done)
            self.sessionTargetApp = nil
            self.resetToIdleSoon()
        }
    }

    private func transition(_ newState: WalkieState) {
        state = newState
        Task { await logger.log("state.transition", fields: ["state": newState.label]) }
    }

    private func currentTargetName() -> String {
        (sessionTargetApp ?? detector.currentDecision(config: config).app).name
    }

    private func reactivateTargetApp(_ target: TargetApp) async {
        guard target.pid != 0 else { return }
        if let app = NSRunningApplication(processIdentifier: target.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func resetToIdleSoon() {
        Task {
            let delay: UInt64
            switch state {
            case .error:
                delay = 2_300_000_000
            default:
                delay = 700_000_000
            }
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                if case .done = self.state {
                    self.hud.hide()
                    self.state = .idle
                } else if case .error = self.state {
                    self.hud.hide()
                    self.state = .idle
                }
            }
        }
    }
}
