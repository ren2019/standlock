import SwiftUI
import StandLockCore

struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    /// Held without observing the countdown publishes. Watch the schedules and work mode below.
    let coordinator: AppCoordinator
    @State private var schedules: [Schedule]
    @State private var workMode: WorkScheduleMode
    @FocusState private var listFocused: Bool
    @AppStorage(SettingsDescription.showHelpKey) private var showHelp = true
    /// Observed so a language change re-resolves the search terms. It publishes on nothing else.
    @EnvironmentObject private var languageStore: LanguageStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    init(navigation: SettingsNavigation, coordinator: AppCoordinator) {
        self.navigation = navigation
        self.coordinator = coordinator
        _schedules = State(initialValue: coordinator.schedules)
        _workMode = State(initialValue: coordinator.preferences.workScheduleMode)
    }

    var body: some View {
        // Below the list, not a `safeAreaInset`: rows would scroll under the footer, and a
        // background to stop that would block the glass.
        VStack(spacing: 0) {
            SettingsSearchField(query: $query, isFocused: $searchFocused, onExit: clearSearch)
                .padding(SettingsTokens.sidebarSearchInsets)
            list
            Divider()
            VStack(spacing: SettingsTokens.sidebarFooterSpacing) {
                NextBreakStatus(coordinator: coordinator)
                HStack {
                    Text("Show help")
                    Spacer()
                    // A label beside the switch leaves it nameless to VoiceOver.
                    Toggle("Show help", isOn: $showHelp)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
            .font(SettingsTokens.descriptionFont)
            .foregroundStyle(.secondary)
            .padding(SettingsTokens.sidebarFooterInsets)
        }
    }

    private var list: some View {
        let visible = visiblePages
        return List(selection: selection) {
            rows(SettingsPage.sidebarTopPages.filter(visible.contains))

            let breakPages = SettingsPage.sidebarBreakPages.filter(visible.contains)
            if !breakPages.isEmpty {
                Section("Breaks") {
                    rows(breakPages)
                }
                // macOS 13 lets a sidebar section collapse, which could hide the selected row.
                .collapsible(false)
            }

            let scheduleRows = schedules.filter { visible.contains(.schedule($0.id)) }
            if !scheduleRows.isEmpty || visible.contains(.newSchedule) {
                Section {
                    ForEach(scheduleRows) { schedule in
                        ScheduleSidebarRow(
                            schedule: schedule,
                            status: FixedScheduleStatus(schedule: schedule, mode: workMode),
                            isSelected: navigation.page == .schedule(schedule.id)
                        )
                        .tag(SettingsPage.schedule(schedule.id))
                    }
                    rows([.newSchedule].filter(visible.contains))
                } header: {
                    HStack {
                        Text("Schedules")
                        Spacer()
                        Group {
                            if workMode == .flexible {
                                Text("Inactive")
                            } else {
                                Text("\(schedules.filter(\.isEnabled).count) on")
                            }
                        }
                        .padding(.trailing, SettingsTokens.sidebarHeaderInset)
                    }
                }
                .collapsible(false)
            }

            let bottomPages = SettingsPage.sidebarBottomPages.filter(visible.contains)
            if !bottomPages.isEmpty {
                // Headerless, so these rows do not read as part of Schedules.
                Section {
                    rows(bottomPages)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Over the list, not instead of it: a list that comes back runs `onAppear`, which would
        // take focus from the field mid-word.
        .overlay {
            if visible.isEmpty {
                Text("No results")
                    .foregroundStyle(.secondary)
            }
        }
        .focused($listFocused)
        .onAppear { listFocused = true }
        .onChange(of: navigation.page) { _ in listFocused = true }
        // A stale filter would hide the page being opened.
        .onReceive(navigation.opened) { clearSearch() }
        .onReceive(coordinator.$schedules.removeDuplicates()) { value in
            schedules = value
            navigation.reconcile(scheduleIDs: value.map(\.id))
        }
        .onReceive(coordinator.$preferences.map(\.workScheduleMode).removeDuplicates()) { mode in
            workMode = mode
        }
    }

    private func clearSearch() {
        query = ""
        listFocused = true
    }

    private var visiblePages: Set<SettingsPage> {
        let pages = SettingsPage.sidebarTopPages + SettingsPage.sidebarBreakPages + [.newSchedule]
            + SettingsPage.sidebarBottomPages
        // Resolving the terms takes about 15 ms, which every selection would pay.
        guard !query.isEmpty else { return Set(pages + schedules.map { .schedule($0.id) }) }

        let formTerms = schedules.first.map { terms(of: .schedule($0.id)) } ?? []
        let matchingPages = pages.filter { settingsSearchMatches(query: query, terms: terms(of: $0)) }
        let matchingSchedules = schedules.filter {
            settingsSearchMatches(query: query, terms: [$0.name] + formTerms)
        }
        return Set(matchingPages + matchingSchedules.map { .schedule($0.id) })
    }

    private func terms(of page: SettingsPage) -> [String] {
        page.searchTerms.map(languageStore.string)
    }

    private var selection: Binding<SettingsPage> {
        let navigation = navigation
        return Binding(get: { navigation.page }, set: { navigation.select($0) })
    }

    private func rows(_ pages: [SettingsPage]) -> some View {
        ForEach(pages, id: \.self) { page in
            let isSelected = page == navigation.page
            SettingsSidebarRow(page: page, isSelected: isSelected) {
                if page == .permissions {
                    PermissionBadge(schedules: schedules, isSelected: isSelected)
                }
            }
            .tag(page)
        }
    }
}
