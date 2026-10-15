import SwiftData
import SwiftUI
import Combine
import os

/// Where save failures surface. Saves used to use `try?`, which hid problems completely.
@MainActor final class SaveStatus: ObservableObject {
    static let shared = SaveStatus()
    @Published var failureMessage: String?
}

extension ModelContext {
    private static let log = Logger(subsystem: "com.devaiam.imstudy", category: "persistence")

    /// Saves, and if that fails, logs it and tells the person (instead of failing silently).
    /// Returns whether the save succeeded.
    @discardableResult
    func saveReporting(_ what: String = "changes") -> Bool {
        do {
            try save()
            return true
        } catch {
            Self.log.error("Save failed (\(what, privacy: .public)): \(String(describing: error), privacy: .public)")
            Task { @MainActor in
                SaveStatus.shared.failureMessage =
                    "IMSTUDY couldn't save your \(what). Your last edit may not be stored. " +
                    "Try again, and make a backup if this keeps happening."
            }
            return false
        }
    }
}
