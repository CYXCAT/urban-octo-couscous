import SwiftUI

struct SessionSplitView: View {
    @Environment(AppModel.self) private var appModel
    @Bindable var store: SessionStore

    var body: some View {
        NavigationSplitView {
            SessionListView(store: store)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if store.activeSessionID == nil {
                ContentUnavailableView(
                    "Select a chat",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Create a chat to get started")
                )
            } else {
                ChatView(store: store)
                    .id(store.activeSessionID)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .environment(appModel)
    }
}

struct SessionListView: View {
    @Environment(AppModel.self) private var appModel
    @Bindable var store: SessionStore
    @State private var showingSignOut = false

    var body: some View {
        Group {
            if store.isLoadingSessions && store.sessions.isEmpty {
                ProgressView()
            } else if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No chats yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Tap the button at the top right to create one")
                )
            } else {
                List(selection: Binding(
                    get: { store.activeSessionID },
                    set: { store.select($0) }
                )) {
                    ForEach(store.sessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(session.updatedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(session.id as String?)
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        Task { await store.delete(at: offsets) }
                    }
                }
            }
        }
        .navigationTitle("Chats")
        .safeAreaInset(edge: .bottom) {
            NetworkStatusView()
                .padding(.vertical, 8)
        }
        .refreshable { await store.reloadSessions() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Sign Out") { showingSignOut = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.createSession() }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New chat")
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await appModel.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let email = appModel.user?.email {
                Text(email)
            }
        }
    }
}
