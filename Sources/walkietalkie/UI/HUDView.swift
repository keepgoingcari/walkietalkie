import SwiftUI

struct HUDView: View {
    let targetApp: String
    let status: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status)
                .font(.headline)
            Text("Target: \(targetApp)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel (Esc)", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(minWidth: 320)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }
}
