import XCTest
import SwiftData
@testable import apple_flash_card

@MainActor
final class BackupTests: XCTestCase {

    // MARK: Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Deck.self, configurations: config)
        return ModelContext(container)
    }

    private func write(_ json: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).imstudy")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return url
    }

    private func archive(photoName: String? = nil, photoBytes: Int = 4,
                         imageItems: String = "", inkRefWidth: Double? = nil) -> [String: Any] {
        var card: [String: Any] = [
            "order": 0, "front": "", "back": "", "frontLined": true, "backLined": true,
            "isStarred": false, "textItemsJSON": "", "imageItemsJSON": imageItems,
            "photos": [], "leitnerBox": 2, "dueTime": 0, "reviewCount": 3,
            "correctCount": 2, "lastReviewed": 0,
        ]
        if let name = photoName {
            card["photos"] = [["file": name, "data": Data(repeating: 7, count: photoBytes).base64EncodedString()]]
        }
        if let w = inkRefWidth { card["inkRefWidth"] = w }
        return ["format": "imstudy-backup", "version": 1, "exported": "2026-10-14T00:00:00Z",
                "decks": [["title": "T", "created": "2026-10-14T00:00:00Z", "cards": [card]]]]
    }

    private func allDecks(_ context: ModelContext) throws -> [Deck] {
        try context.fetch(FetchDescriptor<Deck>())
    }

    // MARK: Photo name safety (E1)

    func testSafeNamesAreAccepted() {
        XCTAssertTrue(ImageStore.isSafeName("3F2504E0-4F89-41D3-9A0C-0305E82C3301.jpg"))
        XCTAssertTrue(ImageStore.isSafeName("photo_1.png"))
    }

    func testUnsafeNamesAreRejected() {
        for bad in ["../escape.jpg", "..", ".hidden", "a/b.jpg", "a\\b.jpg", "", "/etc/passwd",
                    "x..y.jpg", String(repeating: "a", count: 200), "name with space.jpg", "é.jpg"] {
            XCTAssertFalse(ImageStore.isSafeName(bad), "should reject \(bad.debugDescription)")
        }
    }

    func testPathTraversalBackupIsRejectedAndWritesNothing() throws {
        let context = try makeContext()
        let escape = ImageStore.storageDirectory.deletingLastPathComponent()
            .appendingPathComponent("escape.jpg")
        try? FileManager.default.removeItem(at: escape)

        let url = try write(archive(photoName: "../escape.jpg"))
        XCTAssertThrowsError(try Backup.importArchive(from: url, into: context)) { error in
            XCTAssertEqual(error as? Backup.BackupError, .unsafeContents)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: escape.path),
                       "a file was written outside the photo folder")
        XCTAssertTrue(try allDecks(context).isEmpty, "a rejected backup must leave no decks")
    }

    func testOversizedPhotoIsRejected() throws {
        let context = try makeContext()
        let url = try write(archive(photoName: "big.jpg", photoBytes: Backup.maxPhotoBytes + 1))
        XCTAssertThrowsError(try Backup.importArchive(from: url, into: context)) { error in
            XCTAssertEqual(error as? Backup.BackupError, .tooLarge)
        }
        XCTAssertTrue(try allDecks(context).isEmpty)
    }

    func testUnsafePhotoReferencesAreDroppedFromCards() {
        let json = #"[{"id":"\#(UUID().uuidString)","side":0,"file":"../etc/passwd","aspect":1,"x":0,"y":0,"w":0.4},"#
            + #"{"id":"\#(UUID().uuidString)","side":0,"file":"good.jpg","aspect":1,"x":0,"y":0,"w":0.4}]"#
        let cleaned = Backup.sanitizedImageItems(json)
        XCTAssertTrue(cleaned.contains("good.jpg"))
        XCTAssertFalse(cleaned.contains("passwd"))
    }

    // MARK: Ink scale (E2)

    func testInkRefWidthIsRestored() throws {
        let context = try makeContext()
        let url = try write(archive(inkRefWidth: 1180))
        _ = try Backup.importArchive(from: url, into: context)
        let card = try XCTUnwrap(allDecks(context).first?.cards.first)
        XCTAssertEqual(card.inkRefWidth, 1180)
    }

    func testOlderBackupWithoutInkRefWidthStillRestores() throws {
        let context = try makeContext()
        let url = try write(archive())          // no inkRefWidth key at all
        let result = try Backup.importArchive(from: url, into: context)
        XCTAssertEqual(result.decks, 1)
        XCTAssertEqual(result.cards, 1)
        let card = try XCTUnwrap(allDecks(context).first?.cards.first)
        XCTAssertEqual(card.inkRefWidth, 0)
        XCTAssertEqual(card.leitnerBox, 2)      // study progress carried over
        XCTAssertEqual(card.reviewCount, 3)
    }

    // MARK: Round trip

    func testExportThenImportRoundTrip() throws {
        let source = try makeContext()
        let deck = Deck(title: "Round trip")
        source.insert(deck)
        let card = deck.newCard()
        card.inkRefWidth = 952
        card.isStarred = true
        card.leitnerBox = 3
        try source.save()

        let url = try Backup.export([deck], name: "unit-test")
        defer { try? FileManager.default.removeItem(at: url) }

        let target = try makeContext()
        let result = try Backup.importArchive(from: url, into: target)
        XCTAssertEqual(result.decks, 1)
        let restored = try XCTUnwrap(allDecks(target).first?.cards.first)
        XCTAssertEqual(restored.inkRefWidth, 952)
        XCTAssertTrue(restored.isStarred)
        XCTAssertEqual(restored.leitnerBox, 3)
    }

    func testNonBackupFileIsRejected() throws {
        let context = try makeContext()
        let url = try write(["hello": "world"])
        XCTAssertThrowsError(try Backup.importArchive(from: url, into: context)) { error in
            XCTAssertEqual(error as? Backup.BackupError, .notABackup)
        }
    }

    func testNewerVersionIsRejected() throws {
        let context = try makeContext()
        var json = archive()
        json["version"] = 99
        let url = try write(json)
        XCTAssertThrowsError(try Backup.importArchive(from: url, into: context)) { error in
            XCTAssertEqual(error as? Backup.BackupError, .newerVersion)
        }
    }
}

extension Backup.BackupError: @retroactive Equatable {}
