import PortalKit
import SwiftUI

/// SettingsView is where the person's account and the app's preferences live, grouped the way the system Settings groups them. It is
/// a tab when the person puts it on the tab bar, and a row of More otherwise.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    /// Whether Settings is the root of a tab, which floats the tab bar over the list.
    var isTabRoot = false

    @State private var isShowingAccounts = DemoOptions.screen == "accounts"
    @State private var isConfirmingSignOut = false

    private var account: Account { session.account }

    var body: some View {
        List { PortalRows {
            Section {
                Button {
                    isShowingAccounts = true
                } label: {
                    HStack(spacing: 12) {
                        UserAvatar(userId: account.userId, name: account.displayName, hasAvatar: session.profile?.me.hasAvatar, modifiedAt: session.profile?.me.modifiedAt, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName).foregroundStyle(Color.primary)
                            Text(account.server.displayHost).font(.footnote).foregroundStyle(Color.secondary)
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                // A row that opens something reads as a navigation row: plain text, not the accent a Button takes in a list.
                .buttonStyle(.plain)
                .accessibilityIdentifier("accountsButton")
            }
            Section("Notifications") {
                NavigationLink(value: MoreDestination.notificationSettings) {
                    Label("Notification settings", systemImage: "bell.badge")
                        .foregroundStyle(.primary)
                }
            }
            AccountSettingsSection()
            Section("Assistant") {
                NavigationLink(value: MoreDestination.assistantSettings) {
                    Label("Assistant settings", systemImage: "slider.horizontal.3")
                        .foregroundStyle(.primary)
                }
            }
            Section("Tab bar") {
                NavigationLink(value: MoreDestination.tabBarEditor) {
                    Label("Edit tab bar", systemImage: "rectangle.bottomthird.inset.filled")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("editTabBarRow")
            }
            Section {
                NavigationLink(value: MoreDestination.about) {
                    Label("About", systemImage: "info.circle")
                        .foregroundStyle(.primary)
                }
                if let exit = appModel.exitDemo {
                    Button("Exit demo", action: exit)
                } else {
                    Button(role: .destructive) {
                        isConfirmingSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(Color.statusError)
                    }
                    .confirmationDialog("Sign out of this account?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                        Button("Sign out of \(account.displayName)", role: .destructive) { Task { await appModel.remove(account) } }
                    } message: {
                        Text("\(account.displayName) on \(account.server.displayHost) will be removed from this phone.")
                    }
                }
            }
        } }
        .portalList()
        .contentMargins(.bottom, isTabRoot ? 88 : 16, for: .scrollContent)
        .navigationTitle("Settings")
        .sheet(isPresented: $isShowingAccounts) {
            AccountsView()
        }
    }
}

/// TabBarEditorView chooses what is on the tab bar: tap to add a screen, drag to order, and remove the ones that should live under
/// More. The choice is saved per account and applies to the iPad's sidebar too.
struct TabBarEditorView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        let onBar = session.tabSections.filter { $0 != .more && $0 != .search && $0 != TabBar.pinned }
        let rows = [TabBar.pinned] + onBar
        let isFull = onBar.count >= TabBar.capacity - 1
        let others = session.choosableSections.filter { !onBar.contains($0) }
        List { PortalRows {
            Section {
                // A row whose delete is disabled loses the remove control's indent, so Chat carries a lock in that place to line its
                // icon and title up with the rows below it.
                ForEach(rows) { section in
                    Group {
                        if section == TabBar.pinned {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.circle.fill").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(section.titleKey, systemImage: section.symbol)
                                    Text("Always first")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            // A single line that shrinks, so a long name is never broken mid-word at the largest text sizes.
                            Label(section.titleKey, systemImage: section.symbol)
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }
                    }
                    .deleteDisabled(section == TabBar.pinned)
                    .moveDisabled(section == TabBar.pinned)
                }
                .onMove { offsets, destination in
                    guard !offsets.contains(0) else { return }
                    var next = rows
                    next.move(fromOffsets: offsets, toOffset: max(destination, 1))
                    session.setTabBar(Array(next.dropFirst()))
                }
                .onDelete { offsets in
                    var next = rows
                    next.remove(atOffsets: IndexSet(offsets.filter { $0 != 0 }))
                    session.setTabBar(Array(next.dropFirst()))
                }
            } header: {
                Text("In the tab bar")
            } footer: {
                if isFull {
                    Text("The tab bar is full. Remove a screen to add another. More always stays last.")
                } else {
                    Text("More always stays last and holds everything else.")
                }
            }
            if !others.isEmpty {
                Section("More") {
                    ForEach(others) { section in
                        Button {
                            session.setTabBar(onBar + [section])
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill").foregroundStyle(Color.green)
                                Label(section.titleKey, systemImage: section.symbol)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1).minimumScaleFactor(0.5)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isFull)
                    }
                }
            }
            Section {
                Button("Reset to default", role: .destructive) { session.setTabBar(nil) }
                    .disabled(session.savedTabBar == nil)
            }
        } }
        .portalList()
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Edit tab bar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
