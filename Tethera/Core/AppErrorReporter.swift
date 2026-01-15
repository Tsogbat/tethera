import Foundation

struct AppErrorMessage: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String
    let timestamp: Date

    init(title: String, message: String, timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.message = message
        self.timestamp = timestamp
    }
}

@MainActor
final class AppErrorReporter: ObservableObject {
    static let shared = AppErrorReporter()

    @Published var current: AppErrorMessage?

    private init() {}

    func report(title: String, message: String) {
        current = AppErrorMessage(title: title, message: message)
    }

    func clear() {
        current = nil
    }
}
