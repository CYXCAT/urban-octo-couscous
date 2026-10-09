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
                    "选择一个对话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("新建对话后即可开始")
                )
            } else {
                ChatView(store: store)
                    .id(store.activeSessionID)
            }
        }
        .alert("出错了", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
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
                    "还没有对话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("点右上角新建")
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
        .navigationTitle("对话")
        .refreshable { await store.reloadSessions() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("退出") { showingSignOut = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.createSession() }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新对话")
            }
        }
        .confirmationDialog("退出登录？", isPresented: $showingSignOut, titleVisibility: .visible) {
            Button("退出", role: .destructive) {
                Task { await appModel.signOut() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let email = appModel.user?.email {
                Text(email)
            }
        }
    }
}
