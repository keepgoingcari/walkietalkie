import AppKit
import Foundation

struct TargetApp: Sendable {
    let name: String
    let bundleID: String
    let pid: pid_t
}

struct TargetAppDecision: Sendable {
    let app: TargetApp
    let allowed: Bool
    let reasonIfBlocked: String?
}

struct TargetAppDetector {
    private let knownTerminalLikeBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.vscodium",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "io.alacritty",
        "org.wezfurlong.wezterm",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper"
    ]

    func currentTargetApp() -> TargetApp {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return TargetApp(name: "Unknown", bundleID: "unknown", pid: 0)
        }
        return TargetApp(
            name: app.localizedName ?? "Unknown",
            bundleID: app.bundleIdentifier ?? "unknown",
            pid: app.processIdentifier
        )
    }

    func currentDecision(config: WalkieConfig, targetApp: TargetApp? = nil) -> TargetAppDecision {
        let target = targetApp ?? currentTargetApp()
        if target.bundleID == "unknown" {
            let fallback = TargetApp(name: "Unknown", bundleID: "unknown", pid: 0)
            return TargetAppDecision(app: fallback, allowed: config.injection.injectAnywhere, reasonIfBlocked: "No frontmost app")
        }
        if config.injection.injectAnywhere {
            return TargetAppDecision(app: target, allowed: true, reasonIfBlocked: nil)
        }

        let allowlist = Set(config.injection.allowlistBundleIDs)
        if allowlist.contains(target.bundleID) || knownTerminalLikeBundleIDs.contains(target.bundleID) {
            return TargetAppDecision(app: target, allowed: true, reasonIfBlocked: nil)
        }

        return TargetAppDecision(
            app: target,
            allowed: false,
            reasonIfBlocked: "\(target.name) (\(target.bundleID)) is not in allowlist and inject_anywhere=false"
        )
    }
}
