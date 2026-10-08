import SwiftUI
import SwiftData
import UIKit

/// Backup and restore: decks are written to a single `.imstudy` file (JSON) that holds
/// every card's ink, text boxes, photos and study progress. Importing always adds the
/// decks as new ones, so it never overwrites what's already in the app.
enum Backup {
    struct Archive: Codable {
        var format = "imstudy-backup"
        var version = 1
        var exported: Date
        var decks: [DeckDTO]
    }

    struct DeckDTO: Codable {
        var title: String
        var created: Date
        var cards: [CardDTO]
    }

    struct CardDTO: Codable {
        var order: Int
        var front: Data
        var back: Data
        var frontLined: Bool
        var backLined: Bool
        var isStarred: Bool
        var textItemsJSON: String
        var imageItemsJSON: String
        var photos: [PhotoDTO]
        var leitnerBox: Int
        var dueTime: Double
        var reviewCount: Int
        var correctCount: Int
        var lastReviewed: Double
    }

    struct PhotoDTO: Codable {
        var file: String
        var data: Data
    }

    struct ImportResult {
        var decks = 0
        var cards = 0
    }

    enum BackupError: LocalizedError {
        case notABackup
        case newerVersion

        var errorDescription: String? {
            switch self {
            case .notABackup: "That file isn't an IMSTUDY backup."
            case .newerVersion: "That backup was made by a newer version of IMSTUDY."
            }
        }
    }

    // MARK: Export

    /// Writes the given decks to a temporary `.imstudy` file and returns its URL.
    @MainActor static func export(_ decks: [Deck], name: String) throws -> URL {
        let archive = Archive(exported: .now, decks: decks.map(dto(for:)))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe.isEmpty ? "IMSTUDY" : safe) \(stamp).imstudy")
        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor private static func dto(for deck: Deck) -> DeckDTO {
        DeckDTO(title: deck.title, created: deck.created, cards: deck.sortedCards.map(dto(for:)))
    }

    @MainActor private static func dto(for card: Card) -> CardDTO {
        // Text is exported as boxes, which also carries over text from older versions.
        let textJSON = (try? JSONEncoder().encode(card.allTextItems))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let photos = card.allImageItems.compactMap { item in
            ImageStore.fileData(item.file).map { PhotoDTO(file: item.file, data: $0) }
        }
        return CardDTO(
            order: card.order, front: card.front, back: card.back,
            frontLined: card.frontLined, backLined: card.backLined, isStarred: card.isStarred,
            textItemsJSON: textJSON, imageItemsJSON: card.imageItemsJSON, photos: photos,
            leitnerBox: card.leitnerBox, dueTime: card.dueTime, reviewCount: card.reviewCount,
            correctCount: card.correctCount, lastReviewed: card.lastReviewed)
    }

    // MARK: Import

    /// Adds the decks in a backup file as new decks.
    @MainActor static func importArchive(from url: URL, into context: ModelContext) throws -> ImportResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(Archive.self, from: data),
              archive.format == "imstudy-backup" else { throw BackupError.notABackup }
        guard archive.version <= 1 else { throw BackupError.newerVersion }

        var result = ImportResult()
        for d in archive.decks {
            let deck = Deck(title: d.title)
            deck.created = d.created
            context.insert(deck)
            for c in d.cards {
                let card = Card(order: c.order)
                card.front = c.front
                card.back = c.back
                card.frontLined = c.frontLined
                card.backLined = c.backLined
                card.isStarred = c.isStarred
                card.textItemsJSON = c.textItemsJSON
                card.imageItemsJSON = c.imageItemsJSON
                card.leitnerBox = c.leitnerBox
                card.dueTime = c.dueTime
                card.reviewCount = c.reviewCount
                card.correctCount = c.correctCount
                card.lastReviewed = c.lastReviewed
                for photo in c.photos { ImageStore.write(photo.data, as: photo.file) }
                deck.cards.append(card)
                result.cards += 1
            }
            result.decks += 1
        }
        try context.save()
        return result
    }
}

/// The system share sheet (AirDrop, Save to Files, Mail...) for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Wraps a URL so it can drive `.sheet(item:)`.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}
