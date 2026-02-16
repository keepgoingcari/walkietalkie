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
    private let agentHUD = AgentConversationWindowController()
    private let logger = EventLogger.shared

    private var config: WalkieConfig = .default
    private var sttProvider: STTProvider = MockSTTProvider()
    private var llmProvider: LLMProvider = MockLLMProvider()
    private var isCanceled = false
    private var sessionTargetApp: TargetApp?
    private var agentConversationContinuation: CheckedContinuation<String, Error>?
    private var agentConversationTurns: [AgentTurn] = []
    private var agentConversationInitialRequest: String = ""
    private var isAgentConversationFinishing = false
    private var isAgentVoiceTurnRecording = false
    private var isAgentPartnerRunning = false

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
        finishAgentConversation(.failure(WalkieError.canceled))
        Task {
            await audioRecorder.cancelAndDiscard()
        }
        agentHUD.hide()
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
        if mode == .agent, case .agentConversation = state {
            handleAgentConversationHotkey(phase: phase)
            return
        }

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
                        if (error as? WalkieError) == .nothingRecorded || (error as? WalkieError) == .canceled {
                            self.hud.hide()
                            self.agentHUD.hide()
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

    private func handleAgentConversationHotkey(phase: HotkeyPhase) {
        switch phase {
        case .pressed:
            guard !isAgentVoiceTurnRecording else { return }
            isAgentVoiceTurnRecording = true
            agentHUD.setStatus("Listening... release hotkey to send voice turn.")
            agentHUD.setError(nil)
            Task {
                do {
                    try await audioRecorder.start()
                    await logger.log("agent.voice_turn.recording.started")
                } catch {
                    await logger.log("agent.voice_turn.recording.error", fields: ["error": error.localizedDescription])
                    await MainActor.run {
                        self.isAgentVoiceTurnRecording = false
                        self.agentHUD.setStatus(nil)
                        self.agentHUD.setError(error.localizedDescription)
                    }
                }
            }

        case .released:
            guard isAgentVoiceTurnRecording else { return }
            isAgentVoiceTurnRecording = false
            Task {
                do {
                    let audioURL = try await audioRecorder.stop()
                    let transcript = try await sttProvider.transcribe(audioURL: audioURL)
                    try? FileManager.default.removeItem(at: audioURL)
                    await logger.log("agent.voice_turn.transcribed", fields: ["chars": "\(transcript.count)"])
                    await MainActor.run {
                        self.agentHUD.setStatus(nil)
                    }
                    try await appendAgentUserTurnAndRespond(transcript, source: "voice")
                } catch {
                    await MainActor.run {
                        self.agentHUD.setStatus(nil)
                        if (error as? WalkieError) != .nothingRecorded {
                            self.agentHUD.setError(error.localizedDescription)
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
            textToInject = try await runInteractiveAgentSession(initialTranscript: transcript)
            await logger.log("agent.condense.success", fields: ["chars": "\(textToInject.count)"])
        }

        if isCanceled { throw WalkieError.canceled }
        try await preInjectAndSend(text: textToInject, mode: mode)
    }

    private func runInteractiveAgentSession(initialTranscript: String) async throws -> String {
        await MainActor.run {
            self.transition(.agentConversation)
            self.hud.hide()
            self.agentConversationInitialRequest = initialTranscript
            self.agentConversationTurns = [.init(role: .user, content: initialTranscript)]
            self.isAgentConversationFinishing = false
            self.isAgentVoiceTurnRecording = false
            self.isAgentPartnerRunning = false
            self.agentHUD.replaceMessages([AgentHUDMessage(role: .user, content: initialTranscript)])
            self.agentHUD.setError(nil)
            self.agentHUD.setStatus("Tip: hold agent hotkey to add voice turns.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.agentConversationContinuation = continuation

            self.agentHUD.show(
                targetApp: self.currentTargetName(),
                onSend: { [weak self] text in
                    guard let self else { return }
                    Task { @MainActor in
                        do {
                            try await self.appendAgentUserTurnAndRespond(text, source: "typed")
                        } catch {
                            self.agentHUD.setError(error.localizedDescription)
                        }
                    }
                },
                onFinalize: { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in
                        do {
                            let finalPrompt = try await self.llmProvider.condenseConversation(
                                initialRequest: self.agentConversationInitialRequest,
                                history: self.agentConversationTurns
                            )
                            self.finishAgentConversation(.success(finalPrompt))
                        } catch {
                            self.agentHUD.setError(error.localizedDescription)
                        }
                    }
                },
                onInjectLast: { [weak self] in
                    guard let self else { return }
                    let best = self.agentConversationTurns.reversed().first(where: { $0.role == .assistant })?.content
                        ?? self.agentConversationTurns.last(where: { $0.role == .user })?.content
                    guard let text = best, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.agentHUD.setError("No message available to inject yet.")
                        return
                    }
                    self.finishAgentConversation(.success(text))
                },
                onCancel: {
                    self.finishAgentConversation(.failure(WalkieError.canceled))
                }
            )

            Task { @MainActor in
                do {
                    try await self.requestAgentPartnerReply()
                } catch {
                    self.agentHUD.setError(error.localizedDescription)
                }
            }
        }
    }

    private func appendAgentUserTurnAndRespond(_ rawText: String, source: String) async throws {
        guard agentConversationContinuation != nil else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        agentHUD.setError(nil)
        agentHUD.setStatus(nil)
        agentHUD.appendMessage(.init(role: .user, content: text))
        agentConversationTurns.append(.init(role: .user, content: text))
        await logger.log("agent.turn.user", fields: ["source": source, "chars": "\(text.count)"])
        try await requestAgentPartnerReply()
    }

    private func requestAgentPartnerReply() async throws {
        guard agentConversationContinuation != nil else { return }
        guard !isAgentPartnerRunning else { return }

        isAgentPartnerRunning = true
        agentHUD.setThinking(true)
        defer {
            isAgentPartnerRunning = false
            agentHUD.setThinking(false)
        }

        let reply = try await llmProvider.collaborate(history: agentConversationTurns)
        agentConversationTurns.append(.init(role: .assistant, content: reply))
        await logger.log("agent.partner.success", fields: ["chars": "\(reply.count)"])
        agentHUD.appendMessage(.init(role: .assistant, content: reply))
    }

    private func finishAgentConversation(_ result: Result<String, Error>) {
        guard !isAgentConversationFinishing, let continuation = agentConversationContinuation else { return }
        isAgentConversationFinishing = true
        agentConversationContinuation = nil
        isAgentVoiceTurnRecording = false
        isAgentPartnerRunning = false
        agentHUD.hide()
        switch result {
        case .success(let text):
            continuation.resume(returning: text)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        agentConversationTurns = []
        agentConversationInitialRequest = ""
        isAgentConversationFinishing = false
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
