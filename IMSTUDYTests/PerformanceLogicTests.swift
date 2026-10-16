import XCTest
import SwiftData
@testable import apple_flash_card

@MainActor
final class ItemCacheTests: XCTestCase {
    func testDecodesAndReturnsSameValueTwice() throws {
        let card = Card(order: 0)
        card.updateTextItem(TextItem(side: 0, text: "Hello"))
        XCTAssertEqual(card.textItems(.front).map(\.text), ["Hello"])
        XCTAssertEqual(card.textItems(.front).map(\.text), ["Hello"])   // second read (cached)
    }

    func testChangedJSONIsNotServedFromStaleCache() {
        let card = Card(order: 0)
        var item = TextItem(side: 0, text: "One")
        card.updateTextItem(item)
        XCTAssertEqual(card.textItems(.front).first?.text, "One")
        item.text = "Two"
        card.updateTextItem(item)
        XCTAssertEqual(card.textItems(.front).first?.text, "Two")
    }

    func testPhotoItemsDecode() {
        let card = Card(order: 0)
        card.updateImageItem(ImageItem(side: 1, file: "a.jpg", aspect: 0.5))
        XCTAssertEqual(card.imageItems(.back).count, 1)
        XCTAssertEqual(card.imageItems(.front).count, 0)
    }

    func testMovingPhotoLayersChangesOrder() {
        let card = Card(order: 0)
        let a = ImageItem(side: 0, file: "a.jpg", aspect: 1)
        let b = ImageItem(side: 0, file: "b.jpg", aspect: 1)
        let c = ImageItem(side: 0, file: "c.jpg", aspect: 1)
        [a, b, c].forEach { card.updateImageItem($0) }
        card.moveImage(a.id, .toFront)
        XCTAssertEqual(card.allImageItems.map(\.file), ["b.jpg", "c.jpg", "a.jpg"])
        card.moveImage(a.id, .toBack)
        XCTAssertEqual(card.allImageItems.map(\.file), ["a.jpg", "b.jpg", "c.jpg"])
        card.moveImage(b.id, .forward)
        XCTAssertEqual(card.allImageItems.map(\.file), ["a.jpg", "c.jpg", "b.jpg"])
        card.moveImage(b.id, .backward)
        XCTAssertEqual(card.allImageItems.map(\.file), ["a.jpg", "b.jpg", "c.jpg"])
    }
}

@MainActor
final class HandwritingIndexTests: XCTestCase {
    func testFingerprintIsStableAndSensitive() {
        let a = Data([1, 2, 3, 4])
        XCTAssertEqual(HandwritingIndex.fingerprint(a), HandwritingIndex.fingerprint(a))
        XCTAssertNotEqual(HandwritingIndex.fingerprint(a), HandwritingIndex.fingerprint(Data([1, 2, 3, 5])))
        XCTAssertEqual(HandwritingIndex.fingerprint(Data()), HandwritingIndex.fingerprint(Data()))
    }

    func testIndexingTwiceDoesNoSecondRound() async throws {
        let context = ModelContext(try AppStore_.makeContainer(inMemory: true))
        let deck = Deck(title: "T")
        context.insert(deck)
        _ = deck.newCard()
        _ = deck.newCard()
        try context.save()

        var firstReports: [Int] = []
        await HandwritingIndex.indexAll(in: context) { firstReports.append($0) }
        XCTAssertEqual(firstReports.first, 4, "2 cards x 2 sides should be queued the first time")
        XCTAssertEqual(firstReports.last, 0)

        var secondReports: [Int] = []
        await HandwritingIndex.indexAll(in: context) { secondReports.append($0) }
        XCTAssertEqual(secondReports, [0], "nothing changed, so nothing should be re-read")
    }
}

@MainActor
final class TrashLogicTests: XCTestCase {
    func testDaysLeftCountsDown() {
        let now = Date()
        XCTAssertEqual(Trash.daysLeft(deletedAt: now.timeIntervalSince1970, now: now), 30)
        XCTAssertEqual(Trash.daysLeft(deletedAt: now.addingTimeInterval(-10 * 86_400).timeIntervalSince1970, now: now), 20)
        XCTAssertEqual(Trash.daysLeft(deletedAt: now.addingTimeInterval(-40 * 86_400).timeIntervalSince1970, now: now), 0)
    }

    func testPurgeRemovesOnlyExpiredItems() throws {
        let context = ModelContext(try AppStore_.makeContainer(inMemory: true))
        let now = Date()
        let old = Deck(title: "old"); old.deletedAt = now.addingTimeInterval(-31 * 86_400).timeIntervalSince1970
        let recent = Deck(title: "recent"); recent.deletedAt = now.addingTimeInterval(-5 * 86_400).timeIntervalSince1970
        let live = Deck(title: "live")
        [old, recent, live].forEach { context.insert($0) }
        try context.save()

        Trash.purgeExpired(in: context, now: now)
        let titles = try context.fetch(FetchDescriptor<Deck>()).map(\.title).sorted()
        XCTAssertEqual(titles, ["live", "recent"])
    }
}

@MainActor
final class PDFExportTests: XCTestCase {
    func testPDFHasFrontAndBackPagesAndMirrorsBacks() throws {
        let context = ModelContext(try AppStore_.makeContainer(inMemory: true))
        let deck = Deck(title: "Print/Test")
        context.insert(deck)
        for _ in 0..<9 { _ = deck.newCard() }       // 9 cards → 2 groups → 4 pages
        let url = try PDFExport.export(deck)
        let pdf = CGPDFDocument(url as CFURL)
        XCTAssertEqual(pdf?.numberOfPages, 4)
        XCTAssertEqual(url.lastPathComponent, "Print-Test.pdf")
        let front = PDFExport.frame(slot: 0, mirrored: false)
        let back = PDFExport.frame(slot: 0, mirrored: true)
        XCTAssertEqual(front.minX + back.maxX, PDFExport.page.width, accuracy: 0.01)
    }

    func testEmptyDeckStillProducesAPage() throws {
        let deck = Deck(title: "Empty")
        let url = try PDFExport.export(deck)
        XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, 1)
    }
}

@MainActor
final class PhotoOpacityTests: XCTestCase {
    func testOpacitySurvivesSaveAndIsSeenByEveryReader() throws {
        let context = ModelContext(try AppStore_.makeContainer(inMemory: true))
        let deck = Deck(title: "D"); context.insert(deck)
        let card = deck.newCard()
        var item = ImageItem(side: 0, file: "x.jpg", aspect: 0.75)
        card.updateImageItem(item)
        item.opacity = 0.4
        card.updateImageItem(item)
        XCTAssertEqual(card.imageItems(.front).first?.opacity, 0.4)
        XCTAssertTrue(card.imageItemsJSON.contains("0.4"))
        // Moving the photo afterwards must not drop the opacity.
        var moved = card.imageItem(item.id)!
        moved.x = 0.1
        card.updateImageItem(moved)
        XCTAssertEqual(card.imageItem(item.id)?.opacity, 0.4)
    }
}
