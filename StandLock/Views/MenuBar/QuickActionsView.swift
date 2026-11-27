import SwiftUI
import StandLockCore

struct QuickActionsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var languageStore: LanguageStore
    @Environment(\.openWindow) private var openWindow
    @State private var isConfirmingQuit = false

    var body: some View {
        // Tight spacing leaves the two equal pills room for the longest title, Turkish "Duraklat".
        HStack(spacing: 5) {
            if coordinator.isPaused {
                Button {
                    coordinator.resumeSchedule()
                } label: {
                    MenuBarPillLabel("Resume", symbol: "play.fill")
                }
                .buttonStyle(MenuBarPillStyle())
            } else {
                Button {
                    coordinator.skipNextBreak()
                } label: {
                    MenuBarPillLabel("Skip", symbol: "forward.end")
                }
                .buttonStyle(MenuBarPillStyle())
                // Kit ignores both while a session runs: Stop ends it.
                .disabled(coordinator.currentScheduleSettings == nil || coordinator.isBreakActive || inSession
                          || (coordinator.preferences.workScheduleMode == .flexible
                              && coordinator.nextBreakTime == nil && coordinator.deferralReason == nil))

                Button {
                    showPauseMenu()
                } label: {
                    MenuBarPillLabel("Pause", symbol: "pause.circle")
                }
                .buttonStyle(MenuBarPillStyle())
                .disabled((coordinator.schedules.isEmpty && coordinator.preferences.workScheduleMode == .fixed) || inSession)
            }

            iconButton("About StandLock", symbol: "info.circle") {
                coordinator.settingsNavigation.open(.about, using: openWindow)
            }

            iconButton("Settings", symbol: "gearshape") {
                coordinator.settingsNavigation.open(.general, using: openWindow)
            }

            iconButton("Quit StandLock", symbol: "power") {
                isConfirmingQuit = true
            }
            .disabled(coordinator.isBreakActive)
            .popover(isPresented: $isConfirmingQuit, arrowEdge: .bottom) {
                // A popover is a new hosting root, so the language does not reach it otherwise.
                LocalizedRoot(store: languageStore) {
                    QuitConfirmationView(cancel: { isConfirmingQuit = false }, quit: { NSApp.terminate(nil) })
                }
            }
        }
    }

    private var inSession: Bool { coordinator.pomodoroStatus != nil }

    private let pauseDurations: [(title: LocalizedStringResource, seconds: TimeInterval)] = [
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("4 hours", 4 * 60 * 60),
        ("8 hours", 8 * 60 * 60),
        ("12 hours", 12 * 60 * 60),
        ("24 hours", 24 * 60 * 60),
    ]

    private func iconButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(MenuBarPillStyle())
        .frame(width: 28)
        .help(title)
        .accessibilityLabel(title)
    }

    private func showPauseMenu() {
        let handler = PauseMenuHandler(coordinator: coordinator)
        let menu = NSMenu()

        for duration in pauseDurations {
            let item = NSMenuItem(
                title: languageStore.string(duration.title),
                action: #selector(PauseMenuHandler.pause(_:)), keyEquivalent: ""
            )
            item.target = handler
            item.representedObject = duration.seconds
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

@MainActor
private final class PauseMenuHandler: NSObject {
    let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    @objc func pause(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? TimeInterval else { return }
        coordinator.pauseSchedule(for: duration)
    }
}
