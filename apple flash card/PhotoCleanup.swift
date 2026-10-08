import Foundation
import SwiftData

/// Photo files are stored outside the card database, so deleting a card, deck or photo
/// leaves its file behind. This finds files no card refers to and removes them.
enum PhotoCleanup {
    struct Report {
        var files = 0
        var bytes = 0
    }

    /// Files on disk that no card currently uses.
    @MainActor static func unused(in context: ModelContext) -> [(name: String, bytes: Int)] {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let used = Set(cards.flatMap { $0.allImageItems.map(\.file) })
        return ImageStore.storedFiles().filter { !used.contains($0.name) }
    }

    /// Removes unused photo files. Skipped while an undo is still on offer, because
    /// undoing a delete brings its photos back.
    @MainActor @discardableResult
    static func run(in context: ModelContext, force: Bool = false) -> Report {
        if !force && UndoCenter.shared.message != nil { return Report() }
        let orphans = unused(in: context)
        ImageStore.delete(orphans.map(\.name))
        return Report(files: orphans.count, bytes: orphans.reduce(0) { $0 + $1.bytes })
    }
}
