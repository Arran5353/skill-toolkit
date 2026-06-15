import Foundation

public struct ScanWarning: Equatable, Sendable {
    public let filePath: String
    public let message: String
    public init(filePath: String, message: String) {
        self.filePath = filePath
        self.message = message
    }
}
