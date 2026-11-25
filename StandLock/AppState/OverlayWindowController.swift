import AppKit
import SwiftUI
import StandLockCore
import Locking

@MainActor
final class OverlayWindowController: LockPresenting {
    private var overlayWindows: [BreakOverlayWindow] = []
    private var eventTapController: EventTapController?
    private var screenObserver: NSObjectProtocol?
    private var focusTimer: Timer?
    /// Held while a Pomodoro focus cover is up: the user works away from the Mac, and an idle
    /// display sleep would lock the session, take the cover down and lose its end cue.
    private var keepAwake: NSObjectProtocol?
    private let mediaController = MediaController()
    private let languageStore: LanguageStore
    private let themeStore: ThemeStore
    private(set) var isShowing: Bool = false

    private var currentLevel: DisciplineLevel?
    private var currentDuration: TimeInterval = 0
    private var currentExercise: Exercise?
    private var currentPreferences: AppPreferences?
    private var currentStatistics: BreakStatistics?
    private var currentEscalationTier: Int = 0
    private var currentNextIntervalLabel: String?
    private var currentCanPostpone = false
    private var currentPomodoroChip: PomodoroChip?
    private var endDate: Date = .distantPast
    private var waitsForReturn = false
    private var isScheduledBreak = false
    private var flexibleProgress: FlexibleBreakProgress?
    private var presentationID: UUID?
    private var lastScreenChangeHandled: Date = .distantPast
    private var policyBeforeOverlay: NSApplication.ActivationPolicy = .accessory

    var onSkip: (() -> Void)?
    var onComplete: (() -> Void)?
    var onEscape: (() -> Void)?
    var onPostpone: (() -> Void)?

    nonisolated init(languageStore: LanguageStore, themeStore: ThemeStore) {
        self.languageStore = languageStore
        self.themeStore = themeStore
    }

    func showOverlay(
        level: DisciplineLevel, duration: TimeInterval,
        exercise: Exercise?, preferences: AppPreferences,
        statistics: BreakStatistics, escalationTier: Int = 0,
        nextIntervalLabel: String? = nil, canPostpone: Bool = false,
        pomodoroChip: PomodoroChip? = nil, waitsForReturn: Bool = false, isScheduledBreak: Bool,
        flexibleProgress: FlexibleBreakProgress?
    ) {
        // An app-modal alert (a permission restart, Sparkle) sits below the overlay and takes
        // every click from it, Skip included, until the break ends. Closing it returns `.abort`.
        if NSApp.modalWindow != nil { NSApp.abortModal() }
        dismissOverlay()
        presentationID = UUID()
        endDate = Date().addingTimeInterval(duration)
        self.waitsForReturn = waitsForReturn
        self.isScheduledBreak = isScheduledBreak
        self.flexibleProgress = flexibleProgress

        currentLevel = level
        currentDuration = duration
        currentExercise = exercise
        currentPreferences = preferences
        currentStatistics = statistics
        currentEscalationTier = escalationTier
        currentNextIntervalLabel = nextIntervalLabel
        currentCanPostpone = canPostpone
        currentPomodoroChip = pomodoroChip

        createWindows()
        isShowing = true

        // Activate the app, not just the window. A menu bar app stays .accessory and
        // inactive, and an inactive app gets no input method: the escape phrase field
        // then receives raw keystrokes, so Pinyin types `nihao` instead of 你好 and no
        // Chinese, Japanese or Korean phrase can ever be entered. `dismissOverlay`
        // restores the policy saved here; the `dismissOverlay` call above has already
        // put back any earlier one, so this is the policy from before the break.
        policyBeforeOverlay = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if level == .strict {
            startEventTap(preferences: preferences)
            if waitsForReturn && endDate <= Date() {
                eventTapController?.stopBlockingInput()
            }
        }

        forceFocus()
        startFocusEnforcer()

        observeScreenChanges()

        if preferences.pauseMediaDuringBreak {
            mediaController.pause()
        }

        if pomodoroChip?.isFocus == true {
            keepAwake = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled], reason: "Pomodoro focus cover"
            )
        }
    }

    func dismissOverlay() {
        guard isShowing else { return }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        focusTimer?.invalidate()
        focusTimer = nil
        if let keepAwake {
            ProcessInfo.processInfo.endActivity(keepAwake)
            self.keepAwake = nil
        }
        eventTapController?.stop()
        eventTapController = nil

        presentationID = nil
        isShowing = false
        removeWindows()

        // Put back what `showOverlay` saved instead of looking for other visible windows:
        // `NSApp.windows` always holds the menu bar item's visible NSStatusBarWindow, so
        // that check kept the app .regular, with a Dock icon and focus, after every break.
        NSApp.setActivationPolicy(policyBeforeOverlay)
    }

    private func createWindows() {
        guard let id = presentationID, let level = currentLevel,
              let preferences = currentPreferences, let statistics = currentStatistics else { return }
        let look = BreakScreenLook.resolve(
            theme: themeStore.current, level: level, breakScreen: preferences.breakScreen
        )
        for screen in NSScreen.screens {
            let window = BreakOverlayWindow(screen: screen, palette: look.palette, appearance: look.appearance)
            let contentView = ManuscriptBreakView(
                level: level, look: look, totalDuration: currentDuration, endDate: endDate,
                exercise: currentExercise, preferences: preferences,
                statistics: statistics, escalationTier: currentEscalationTier,
                nextIntervalLabel: currentNextIntervalLabel,
                pomodoroChip: currentPomodoroChip,
                canPostpone: currentCanPostpone, waitsForReturn: waitsForReturn,
                isScheduledBreak: isScheduledBreak, flexibleProgress: flexibleProgress,
                onCountdownEnded: { [weak self] in
                    guard self?.presentationID == id else { return }
                    self?.eventTapController?.stopBlockingInput()
                },
                onSkip: { [weak self] in
                    guard let self, self.presentationID == id else { return }
                    if self.isScheduledBreak && Date() >= self.endDate {
                        // A button drawn just before the deadline can still receive the click.
                        if self.flexibleProgress != nil { self.handleComplete() }
                        return
                    }
                    self.handleSkip()
                },
                onPostpone: { [weak self] in
                    guard let self, self.presentationID == id,
                          self.flexibleProgress == nil || Date() < self.endDate else { return }
                    self.handlePostpone()
                },
                onEscape: { [weak self] in
                    guard self?.presentationID == id else { return }
                    self?.handleEscape()
                },
                onComplete: { [weak self] in
                    guard self?.presentationID == id else { return }
                    self?.handleComplete()
                }
            )
            window.setContent(LocalizedRoot(store: languageStore) { contentView })
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }
    }

    private func removeWindows() {
        let windows = overlayWindows
        overlayWindows.removeAll()
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
    }

    private func startEventTap(preferences: AppPreferences) {
        let level = currentLevel ?? .strict
        let policy = level.enforcementPolicy(preferences: preferences)
        let enforcementTier = policy.tier(at: currentEscalationTier)
        let effectiveHold: TimeInterval
        if case .keyCombo(let duration) = enforcementTier.dismissMechanism {
            effectiveHold = duration
        } else {
            effectiveHold = preferences.strictEscapeHoldDuration
        }
        let id = presentationID
        eventTapController = EventTapController(
            escapeHoldDuration: effectiveHold,
            onEscapeTriggered: { [weak self] in
                Task { @MainActor in
                    guard self?.presentationID == id else { return }
                    self?.handleEscape()
                }
            }
        )
        eventTapController?.startBlocking()
    }

    private func handleSkip() {
        dismissOverlay()
        onSkip?()
    }

    private func handlePostpone() {
        dismissOverlay()
        onPostpone?()
    }

    private func handleComplete() {
        dismissOverlay()
        onComplete?()
    }

    private func handleEscape() {
        dismissOverlay()
        onEscape?()
    }

    private func forceFocus() {
        for window in overlayWindows {
            window.orderFrontRegardless()
        }
        if !overlayWindows.contains(where: \.isKeyWindow) {
            overlayWindows.first?.makeKey()
        }
    }

    private func startFocusEnforcer() {
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShowing else { return }
                self.forceFocus()
            }
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenChange()
            }
        }
    }

    private func handleScreenChange() {
        let now = Date()
        guard now.timeIntervalSince(lastScreenChangeHandled) > 2.0 else { return }
        lastScreenChangeHandled = now

        guard isShowing else { return }
        if endDate <= now && !waitsForReturn {
            handleComplete()
            return
        }
        removeWindows()
        createWindows()
        forceFocus()
    }
}
