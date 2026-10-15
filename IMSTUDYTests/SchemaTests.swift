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

    func testV1IsTheOnlyReleasedVersionAndPlanListsIt() {
        XCTAssertEqual(IMSTUDYMigrationPlan.schemas.count, 1)
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }
}
