import SwiftUI

struct ChatView: View {
    @Bindable var store: SessionStore
    @State private var draft = ""

    var body: some View {
        Group {
            if store.messages.isEmpty && !store.isSending {
                ContentUnavailableView(
                    "开始对话",
                    systemImage: "text.bubble",
                    description: Text("发一条消息")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isStreaming: store.isSending && message.id == store.messages.last?.id
                                )
                                .id(message.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: store.messages.last?.content) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    .onChange(of: store.messages.count) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { composer }
        .task { await store.loadMessages() }
    }

    private var title: String {
        store.sessions.first { $0.id == store.activeSessionID }?.title ?? "对话"
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("发送消息", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 18))

            Button {
                let text = draft
                draft = ""
                Task { await store.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            bubble
                .frame(maxWidth: 560, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .assistant && message.content.isEmpty && isStreaming {
                ProgressView()
            } else if message.role == .assistant && !isStreaming, let markdown = markdownText {
                Text(markdown)
            } else {
                Text(message.content)
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var background: Color {
        message.role == .user ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground)
    }

    private var markdownText: AttributedString? {
        try? AttributedString(markdown: message.content)
    }
}
