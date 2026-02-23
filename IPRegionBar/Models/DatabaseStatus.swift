import Foundation

enum DatabaseStatus {
    case missing
    case downloading(progress: Double)
    case ready(updatedAt: Date)
    case outdated(updatedAt: Date)
    case updateFailed(error: Error)
}

enum AppState {
    case onboarding
    case loading
    case loaded(IPInfo)
    case offline(last: IPInfo?)
    case error(String)
}
