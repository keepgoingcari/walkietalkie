import SwiftUI

enum AgentMessageRole {
    case user
    case assistant
}

struct AgentHUDMessage: Identifiable {
    let id = UUID()
    let role: AgentMessageRole
    let content: String
}

@MainActor
final class AgentConversationViewModel: ObservableObject {
    @Published var messages: [AgentHUDMessage] = []
    @Published var draft: String = ""
    @Published var isThinking: Bool = false
    @Published var errorText: String?
    @Published var statusText: String?
}

struct AgentConversationView: View {
    @ObservedObject var model: AgentConversationViewModel
    let targetApp: String
    let onSend: (String) -> Void
    let onFinalize: () -> Void
    let onInjectLast: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.16)
            transcript
            Divider().opacity(0.16)
            composer
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent Partner")
                    .font(.headline)
                Text("Target: \(targetApp)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isThinking {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Inject Last Reply", action: onInjectLast)
                .buttonStyle(.bordered)
            Button("Finalize & Inject", action: onFinalize)
                .buttonStyle(.borderedProminent)
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages) { message in
                        HStack {
                            if message.role == .assistant { bubble(message, color: Color.blue.opacity(0.14)) }
                            Spacer(minLength: 8)
                            if message.role == .user { bubble(message, color: Color.green.opacity(0.14)) }
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: model.messages.count) { _ in
                if let last = model.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorText = model.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let statusText = model.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add constraints, files, acceptance criteria...", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit {
                        sendDraft()
                    }

                Button("Send") {
                    sendDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isThinking)
            }

            HStack(spacing: 8) {
                quickButton("Shorter")
                quickButton("More technical")
                quickButton("Add risks")
                quickButton("Add test plan")
            }
        }
        .padding(12)
    }

    private func quickButton(_ text: String) -> some View {
        Button(text) {
            onSend(text)
        }
        .buttonStyle(.bordered)
        .disabled(model.isThinking)
    }

    private func bubble(_ message: AgentHUDMessage, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role == .user ? "You" : "Agent")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .id(message.id)
    }

    private func sendDraft() {
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.draft = ""
        onSend(text)
    }
}
