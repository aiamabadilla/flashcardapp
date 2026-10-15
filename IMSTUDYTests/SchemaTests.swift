import XCTest
import SwiftData
@testable import apple_flash_card

@MainActor
final class SchemaTests: XCTestCase {

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("schema-\(UUID().uuidString).store")
    }

    func testContainerOpensWithMigrationPlan() throws {
        XCTAssertNoThrow(try AppStore_.makeContainer(inMemory: true))
    }

    func testDataSurvivesReopeningTheStore() throws {
        let url = tempStoreURL()
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        do {
            let container = try AppStore_.makeContainer(url: url)
            let context = ModelContext(container)
            let deck = Deck(title: "Persisted")
            context.insert(deck)
            let card = deck.newCard()
            card.isStarred = true
            card.leitnerBox = 4
            card.inkRefWidth = 952
            try context.save()
        }

        let reopened = try AppStore_.makeContainer(url: url)
        let decks = try ModelContext(reopened).fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks.first?.title, "Persisted")
        let card = try XCTUnwrap(decks.first?.cards.first)
        XCTAssertTrue(card.isStarred)
        XCTAssertEqual(card.leitnerBox, 4)
        XCTAssertEqual(card.inkRefWidth, 952)
    }

    func testPlanListsEveryReleasedVersionInOrder() {
        XCTAssertEqual(IMSTUDYMigrationPlan.schemas.count, 2)
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(SchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(IMSTUDYMigrationPlan.stages.count, 1)
    }

    /// A store written by the first shipped shape (V1) must open under the current app with all
    /// data, including the drawings that moved to external storage.
    func testV1StoreMigratesToV2WithDataIntact() throws {
        let url = tempStoreURL()
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let ink = Data((0..<4096).map { UInt8($0 % 251) })

        do {   // write with the frozen V1 models and no plan, exactly as the first release did
            let schema = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(for: schema,
                                               configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let deck = SchemaV1.Deck(title: "Old deck")
            context.insert(deck)
            let card = SchemaV1.Card(order: 3)
            card.front = ink
            card.back = Data([9, 9, 9])
            card.isStarred = true
            card.leitnerBox = 2
            card.textItemsJSON = #"[{"id":"\#(UUID().uuidString)","side":0,"text":"hi","x":0.1,"y":0.1,"w":0.5,"size":0.03}]"#
            deck.cards.append(card)
            try context.save()
        }

        let migrated = try AppStore_.makeContainer(url: url)
        let decks = try ModelContext(migrated).fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks.first?.title, "Old deck")
        let card = try XCTUnwrap(decks.first?.cards.first)
        XCTAssertEqual(card.order, 3)
        XCTAssertEqual(card.front, ink, "drawing bytes must be identical after migration")
        XCTAssertEqual(card.back, Data([9, 9, 9]))
        XCTAssertTrue(card.isStarred)
        XCTAssertEqual(card.leitnerBox, 2)
        XCTAssertEqual(card.textItems(.front).first?.text, "hi")
    }
}

@MainActor
final class SaveReportingTests: XCTestCase {
    func testSaveReportingSucceedsOnHealthyContext() throws {
        let context = ModelContext(try AppStore_.makeContainer(inMemory: true))
        context.insert(Deck(title: "ok"))
        XCTAssertTrue(context.saveReporting("test"))
        XCTAssertNil(SaveStatus.shared.failureMessage)
    }
}
