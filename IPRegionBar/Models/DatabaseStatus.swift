import Foundation

enum DatabaseStatus {
    case notInstalled
    case installed(month: String)
    case updating
    case updateFailed
}

enum AppState {
    case setupRequired
    case loading
    case loaded(IPInfo)
    case offline(last: IPInfo?)
    case error(String)
}
