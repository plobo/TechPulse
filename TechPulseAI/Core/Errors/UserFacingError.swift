import Foundation

/// Errors translated into actionable, user-presentable states.
enum UserFacingError: Error, Equatable, Sendable {
    case offline
    case server
    case notFound
    case unexpected

    init(_ error: any Error) {
        switch error {
        case APIError.offline: self = .offline
        case let api as APIError where api.isTransient: self = .server
        case APIError.http(status: 404), RepositoryError.notFound: self = .notFound
        case APIError.http: self = .server
        default: self = .unexpected
        }
    }

    var title: String {
        switch self {
        case .offline: "You’re offline"
        case .server: "Service unavailable"
        case .notFound: "Not found"
        case .unexpected: "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case .offline: "Check your connection. Saved articles and notes are still available in Library."
        case .server: "The content service didn’t respond. Please try again shortly."
        case .notFound: "This item is no longer available."
        case .unexpected: "We couldn’t load this content."
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .server: "exclamationmark.icloud"
        case .notFound: "questionmark.folder"
        case .unexpected: "exclamationmark.triangle"
        }
    }

    var actionTitle: String? { self == .notFound ? nil : "Try Again" }
}

enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(UserFacingError)

    var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    var error: UserFacingError? {
        if case let .failed(error) = self { return error }
        return nil
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
