import SwiftData
import UniformTypeIdentifiers

/// Turns a spreadsheet into a deck: column 1 is each card's front, column 2 its back, and
/// row 1 holds the column headers (shown small at the top of each side).
enum SpreadsheetImporter {
    static var types: [UTType] {
        [.commaSeparatedText, .tabSeparatedText, .plainText,
         UTType("org.openxmlformats.spreadsheetml.sheet")].compactMap { $0 }
    }

    struct Result { let title: String; let cards: Int }

    @MainActor
    static func importFile(at url: URL, into context: ModelContext) throws -> Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let table = try SpreadsheetParser.parse(data, fileExtension: url.pathExtension)
        let title = url.deletingPathExtension().lastPathComponent
        let deck = build(table, title: title.isEmpty ? "Imported Deck" : title, in: context)
        _ = deck
        context.saveReporting()
        return Result(title: title, cards: table.rows.count)
    }

    /// Cards are created in spreadsheet order (row 2 first).
    @MainActor
    @discardableResult
    static func build(_ table: SpreadsheetTable, title: String, in context: ModelContext) -> Deck {
        let deck = Deck(title: title)
        context.insert(deck)
        for (index, row) in table.rows.enumerated() {
            let card = Card(order: index)
            card.frontLined = NewCardDefaults.frontLined
            card.backLined = NewCardDefaults.backLined
            deck.cards.append(card)
            for item in SpreadsheetCardLayout.items(front: row[0], back: row[1], headers: table.headers) {
                card.updateTextItem(item)
            }
        }
        return deck
    }
}
