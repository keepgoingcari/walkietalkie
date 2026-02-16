import AppKit
import SwiftUI

struct WalkieTalkieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppContainer.shared.coordinator

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Walkie", systemImage: "waveform") {
            MenuContentView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private final class AppContainer {
    static let shared = AppContainer()
    let coordinator = AppCoordinator()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppContainer.shared.coordinator.start()
        }
    }
}

private struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            Text(coordinator.state.label)
                .font(.caption)
            Divider()
            Button("Reload Config") {
                coordinator.reloadConfig()
            }
            Button("Show Config in Finder") {
                coordinator.openConfigInFinder()
            }
            Button("Show Logs in Finder") {
                coordinator.openLogsInFinder()
            }
            Button("Open Accessibility Settings") {
                AccessibilityService.openAccessibilitySettings()
            }
            Button("Cancel Current Flow") {
                coordinator.cancelCurrentFlow()
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}
