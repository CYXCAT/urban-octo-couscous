import Foundation

struct APIError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

func describeRequestError(_ error: Error) -> String {
    if let apiError = error as? APIError {
        return apiError.message
    }
    if error is CancellationError {
        return "Cancelled"
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
            return "Could not reach the local server. Make sure it is running and that your phone and computer are on the same network."
        default:
            break
        }
    }
    return error.localizedDescription
}
