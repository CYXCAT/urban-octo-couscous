import Foundation

final class APIClient {
    let baseURL: URL
    var token: String?
    var onUnauthorized: (@MainActor () -> Void)?

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func login(idToken: String) async throws -> AuthSession {
        let result: LoginResponse = try await request(
            method: "POST",
            path: ["auth", "google"],
            body: IDTokenBody(idToken: idToken),
            authenticated: false
        )
        token = result.token
        return AuthSession(token: result.token, user: result.user)
    }

    func logout() async {
        guard token != nil else { return }
        let _: OKResponse? = try? await request(method: "POST", path: ["auth", "logout"])
    }

    func currentUser() async throws -> UserProfile {
        let response: UserResponse = try await request(method: "GET", path: ["me"])
        return response.user
    }

    func sessions() async throws -> [ChatSession] {
        let response: SessionListResponse = try await request(method: "GET", path: ["sessions"])
        return response.sessions
    }

    func createSession() async throws -> ChatSession {
        try await request(method: "POST", path: ["sessions"], body: EmptyBody())
    }

    func deleteSession(id: String) async throws {
        let _: OKResponse = try await request(method: "DELETE", path: ["sessions", id])
    }

    func messages(sessionID: String) async throws -> [ChatMessage] {
        let response: MessageListResponse = try await request(
            method: "GET",
            path: ["sessions", sessionID, "messages"]
        )
        return response.messages
    }

    func streamMessage(sessionID: String, content: String) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let urlRequest: URLRequest
        do {
            urlRequest = try makeRequest(
                method: "POST",
                path: ["sessions", sessionID, "messages"],
                body: ContentBody(content: content),
                timeout: 180,
                accept: "text/event-stream"
            )
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError(message: "无效响应")
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        try reject(http, data: data)
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty || payload == "[DONE]" { continue }
                        let event = try APICoding.decoder.decode(ChatStreamEvent.self, from: Data(payload.utf8))
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func request<Response: Decodable>(
        method: String,
        path: [String],
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> Response {
        let urlRequest = try makeRequest(
            method: method,
            path: path,
            body: body,
            timeout: 30,
            accept: "application/json",
            authenticated: authenticated
        )
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "无效响应")
        }
        if !(200..<300).contains(http.statusCode) {
            try reject(http, data: data)
        }
        do {
            return try APICoding.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError(message: "服务器响应无法解析")
        }
    }

    private func makeRequest(
        method: String,
        path: [String],
        body: (any Encodable)?,
        timeout: TimeInterval,
        accept: String,
        authenticated: Bool = true
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: endpoint(path))
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try APICoding.encoder.encode(body)
        }
        if authenticated {
            guard let token else { throw APIError(message: "未登录") }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }

    private func reject(_ http: HTTPURLResponse, data: Data) throws {
        let serverMessage = (try? APICoding.decoder.decode(ErrorResponse.self, from: data))?.error
        if http.statusCode == 401, token != nil {
            onUnauthorized?()
        }
        throw APIError(message: serverMessage ?? "请求失败（\(http.statusCode)）")
    }

    private func endpoint(_ parts: [String]) -> URL {
        parts.reduce(baseURL) { $0.appending(path: $1) }
    }
}

private enum APICoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = APIDate.parse(value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: value)
            }
            return date
        }
        return decoder
    }()

    static let encoder = JSONEncoder()
}

private enum APIDate {
    static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? plain.date(from: value)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct IDTokenBody: Encodable {
    let idToken: String
}

private struct ContentBody: Encodable {
    let content: String
}

private struct EmptyBody: Encodable {}

private struct OKResponse: Decodable {
    let ok: Bool
}

private struct ErrorResponse: Decodable {
    let error: String
}

private struct LoginResponse: Decodable {
    let token: String
    let user: UserProfile
}

private struct UserResponse: Decodable {
    let user: UserProfile
}

private struct SessionListResponse: Decodable {
    let sessions: [ChatSession]
}

private struct MessageListResponse: Decodable {
    let messages: [ChatMessage]
}
