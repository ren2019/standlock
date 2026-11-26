import SwiftUI
import StandLockCore

@main
struct StandLockApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var appCoordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            LocalizedRoot(store: appCoordinator.languageStore) {
                MenuBarView(updater: appDelegate.updaterController.updater)
                    .environmentObject(appCoordinator)
                    .environmentObject(appCoordinator.permissionChecker)
                    .environmentObject(appDelegate.updateObserver)
            }
        } label: {
            let stateLook = MenuSceneLook(state: appCoordinator.nextBreakState, pomodoro: appCoordinator.pomodoroStatus)
            let displayedLook = appCoordinator.pauseMenuBarDisplay?.iconLook ?? stateLook
            ZStack {
                Image(nsImage: MenuBarIcon.make(progress: appCoordinator.breakProgress, look: stateLook))
                    .opacity(displayedLook == stateLook ? 1 : 0)
                Image(nsImage: MenuBarIcon.make(progress: appCoordinator.breakProgress, look: displayedLook))
                    .opacity(displayedLook == stateLook ? 0 : 1)
            }
            .accessibilityLabel(MenuBarIcon.accessibilityLabel(for: stateLook))
            .animation(.easeInOut(duration: 0.2), value: displayedLook)
            if let timerText = appCoordinator.menuBarTimerText {
                Text(timerText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: SettingsNavigation.windowID) {
            LocalizedRoot(store: appCoordinator.languageStore) {
                SettingsView(
                    navigation: appCoordinator.settingsNavigation,
                    coordinator: appCoordinator,
                    updater: appDelegate.updaterController.updater
                )
                    .environmentObject(appCoordinator)
                    .environmentObject(appCoordinator.permissionChecker)
                    .environmentObject(appCoordinator.themeStore)
                    .environmentObject(appDelegate.updateObserver)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        // Before `.commands`: the other order removes those commands too.
        .commandsRemoved()
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenSettingsCommand(navigation: appCoordinator.settingsNavigation)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(
                    updater: appDelegate.updaterController.updater,
                    observer: appDelegate.updateObserver
                )
            }
        }
    }
}
