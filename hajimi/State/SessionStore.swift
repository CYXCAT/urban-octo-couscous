import Foundation
import Observation

@Observable
final class SessionStore {
    private let api: APIClient
    private var loadGeneration = 0
    private var sendingSessionID: String?

    var sessions: [ChatSession] = []
    var messages: [ChatMessage] = []
    var activeSessionID: String?
    var isLoadingSessions = true
    var isSending = false
    var errorMessage: String?

    init(api: APIClient) {
        self.api = api
    }

    func reloadSessions() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            sessions = try await api.sessions()
        } catch {
            errorMessage = describeRequestError(error)
        }
    }

    func createSession() async {
        do {
            let session = try await api.createSession()
            sessions.insert(session, at: 0)
            select(session.id)
        } catch {
            errorMessage = describeRequestError(error)
        }
    }

    func delete(at offsets: IndexSet) async {
        let ids = offsets.map { sessions[$0].id }
        for id in ids {
            do {
                try await api.deleteSession(id: id)
                if activeSessionID == id {
                    select(nil)
                }
                sessions.removeAll { $0.id == id }
            } catch {
                errorMessage = describeRequestError(error)
            }
        }
    }

    func select(_ id: String?) {
        guard activeSessionID != id else { return }
        activeSessionID = id
        messages = []
        errorMessage = nil
        loadGeneration += 1
    }

    func loadMessages() async {
        guard let sessionID = activeSessionID else { return }
        let generation = loadGeneration
        do {
            let loaded = try await api.messages(sessionID: sessionID)
            guard generation == loadGeneration, activeSessionID == sessionID, sendingSessionID != sessionID else { return }
            messages = loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = describeRequestError(error)
        }
    }

    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let sessionID = activeSessionID, !isSending else { return }

        isSending = true
        sendingSessionID = sessionID
        defer {
            isSending = false
            sendingSessionID = nil
        }
        errorMessage = nil

        let userLocalID = "local-user-\(UUID().uuidString)"
        let assistantLocalID = "local-assistant-\(UUID().uuidString)"
        messages.append(ChatMessage(id: userLocalID, role: .user, content: text, createdAt: Date()))
        messages.append(ChatMessage(id: assistantLocalID, role: .assistant, content: "", createdAt: Date()))

        var receivedDelta = false
        do {
            for try await event in api.streamMessage(sessionID: sessionID, content: text) {
                guard activeSessionID == sessionID else { continue }
                switch event.type {
                case "user":
                    if let message = event.message {
                        replace(id: userLocalID, with: message)
                    }
                    if let session = event.session {
                        apply(session)
                    }
                case "delta":
                    guard let delta = event.text, !delta.isEmpty else { continue }
                    receivedDelta = true
                    append(delta, to: assistantLocalID)
                case "done":
                    if let message = event.message {
                        replace(id: assistantLocalID, with: message)
                    }
                    if let session = event.session {
                        apply(session)
                    }
                case "error":
                    errorMessage = event.error ?? "Generation failed"
                    removeEmptyAssistant(id: assistantLocalID)
                default:
                    break
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard activeSessionID == sessionID else { return }
            if !receivedDelta {
                messages.removeAll { $0.id == userLocalID || $0.id == assistantLocalID }
            }
            errorMessage = describeRequestError(error)
        }
    }

    private func replace(id: String, with message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = message
    }

    private func append(_ text: String, to id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += text
    }

    private func removeEmptyAssistant(id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              messages[index].content.isEmpty else { return }
        messages.remove(at: index)
    }

    private func apply(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }
}
