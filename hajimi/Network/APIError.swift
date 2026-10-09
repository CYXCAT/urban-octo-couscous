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
        return "已取消"
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
            return "连不上本机服务。请确认服务器已启动，并且手机和电脑在同一网络。"
        default:
            break
        }
    }
    return error.localizedDescription
}
