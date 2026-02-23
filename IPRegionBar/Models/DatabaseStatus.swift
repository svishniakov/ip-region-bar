import Foundation

enum DatabaseStatus {
    case bundled(month: String)
    case updated(month: String)
    case updating
    case updateFailed
}

enum AppState {
    case loading
    case loaded(IPInfo)
    case offline(last: IPInfo?)
    case error(String)
}
