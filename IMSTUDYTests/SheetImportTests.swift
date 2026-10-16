import XCTest
import SwiftData
import PDFKit
@testable import apple_flash_card

@MainActor
final class SheetImportTests: XCTestCase {

    // MARK: Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Deck.self, configurations: config)
        return ModelContext(container)
    }

    private typealias Row = SheetImport.Row

    private func parse(_ csv: String, ext: String = "csv") throws -> [Row] {
        try SheetImport.parse(Data(csv.utf8), fileExtension: ext)
    }

    /// Written by openpyxl: text stored inline, two sheets, a blank row, a number, a third column.
    private let inlineStringWorkbook = """
        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
        """

    /// Written the way Excel does: shared strings (with rich text and furigana), the leftmost tab
    /// is sheet2.xml, a third column, a number and a boolean.
    private let sharedStringWorkbook = """
        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
        AQAA3gYAAAAA
        """

    private func data(_ base64: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: base64, options: .ignoreUnknownCharacters))
    }

    // MARK: CSV

    func testColumnOneIsFrontAndColumnTwoIsBack() throws {
        let rows = try parse("dog,犬\ncat,猫\n")
        XCTAssertEqual(rows, [Row(front: "dog", back: "犬"), Row(front: "cat", back: "猫")])
    }

    func testEveryRowIsACardIncludingTheFirst() throws {
        let rows = try parse("front,back\nq,a")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], Row(front: "front", back: "back"))
    }

    func testQuotedFieldsCommasQuotesAndLineBreaks() throws {
        let rows = try parse("\"two, words\",\"say \"\"hi\"\"\"\n\"line1\nline2\",x\r\n")
        XCTAssertEqual(rows, [Row(front: "two, words", back: "say \"hi\""),
                              Row(front: "line1\nline2", back: "x")])
    }

    func testByteOrderMarkAndWindowsLineEndings() throws {
        let rows = try SheetImport.parse(Data([0xEF, 0xBB, 0xBF] + Array("a,b\r\nc,d\r\n".utf8)), fileExtension: "csv")
        XCTAssertEqual(rows, [Row(front: "a", back: "b"), Row(front: "c", back: "d")])
    }

    func testSemicolonAndTabSeparatedFiles() throws {
        XCTAssertEqual(try parse("a;b\nc;d", ext: "csv"), [Row(front: "a", back: "b"), Row(front: "c", back: "d")])
        XCTAssertEqual(try parse("a\tb\nc\td", ext: "tsv"), [Row(front: "a", back: "b"), Row(front: "c", back: "d")])
    }

    func testBlankRowsAreSkippedAndExtraColumnsIgnored() throws {
        let rows = try parse("a,b,extra\n,\n  ,  \nonly front,\n,only back\n")
        XCTAssertEqual(rows, [Row(front: "a", back: "b"),
                              Row(front: "only front", back: ""),
                              Row(front: "", back: "only back")])
    }

    func testFileWithNoTextIsAnError() {
        XCTAssertThrowsError(try parse(",\n,\n")) { XCTAssertEqual($0 as? SheetImport.SheetError, .empty) }
        XCTAssertThrowsError(try parse("")) { XCTAssertEqual($0 as? SheetImport.SheetError, .empty) }
    }

    func testBinaryAndOldExcelFilesAreRejected() {
        let oldExcel = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        XCTAssertThrowsError(try SheetImport.parse(oldExcel, fileExtension: "xls")) {
            XCTAssertEqual($0 as? SheetImport.SheetError, .unsupported)
        }
        let binary = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x0D])
        XCTAssertThrowsError(try SheetImport.parse(binary, fileExtension: "csv")) {
            XCTAssertEqual($0 as? SheetImport.SheetError, .unsupported)
        }
    }

    func testTooManyRowsIsRejected() {
        let csv = String(repeating: "a,b\n", count: SheetImport.maxRows + 1)
        XCTAssertThrowsError(try parse(csv)) { XCTAssertEqual($0 as? SheetImport.SheetError, .tooManyRows) }
        XCTAssertNoThrow(try parse(String(repeating: "a,b\n", count: SheetImport.maxRows)))
    }

    func testVeryLongCellsAreTrimmed() throws {
        let rows = try parse(String(repeating: "x", count: SheetImport.maxCellLength + 500) + ",b")
        XCTAssertEqual(rows[0].front.count, SheetImport.maxCellLength)
    }

    // MARK: Excel

    func testInlineStringWorkbookUsesFirstSheetOnly() throws {
        let rows = try SheetImport.parse(try data(inlineStringWorkbook), fileExtension: "xlsx")
        XCTAssertEqual(rows, [
            Row(front: "犬", back: "dog"),
            Row(front: "What is 2 + 2?", back: "4"),
            Row(front: "Line one\nLine two", back: "multi-line front"),
            Row(front: "only front", back: ""),
            Row(front: "has third column", back: "back"),
        ])
    }

    func testSharedStringWorkbookFollowsTabOrderAndSkipsFurigana() throws {
        let rows = try SheetImport.parse(try data(sharedStringWorkbook), fileExtension: "xlsx")
        XCTAssertEqual(rows, [
            Row(front: "水", back: "water"),
            Row(front: "Rich text", back: ""),
            Row(front: "", back: "Capital of France?"),
            Row(front: "42", back: "TRUE"),
        ])
    }

    func testDamagedWorkbookIsAnErrorNotACrash() throws {
        let good = try data(sharedStringWorkbook)
        XCTAssertThrowsError(try SheetImport.parse(Data(good.prefix(good.count / 2)), fileExtension: "xlsx"))
        XCTAssertThrowsError(try SheetImport.parse(Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]), fileExtension: "xlsx"))
    }

    // MARK: Creating cards

    func testImportedRowsBecomeCardsAtTheTopInFileOrder() throws {
        let context = try makeContext()
        let deck = Deck(title: "Spanish")
        context.insert(deck)
        let existing = deck.newCard()

        let added = SheetImport.addCards([Row(front: "perro", back: "dog"), Row(front: "gato", back: "")],
                                         to: deck, in: context)

        XCTAssertEqual(added.count, 2)
        let cards = deck.sortedCards
        XCTAssertEqual(cards.map(\.order), [0, 1, 2])
        XCTAssertTrue(cards[2] === existing)
        XCTAssertEqual(cards[0].textItems(.front).map(\.text), ["perro"])
        XCTAssertEqual(cards[0].textItems(.back).map(\.text), ["dog"])
        XCTAssertEqual(cards[1].textItems(.front).map(\.text), ["gato"])
        XCTAssertTrue(cards[1].textItems(.back).isEmpty)
        XCTAssertTrue(cards[0].isNew)
    }

    func testImportedCardsStartWithBlankFrontAndLinedBack() throws {
        let context = try makeContext()
        let deck = Deck(title: "D")
        context.insert(deck)
        let card = try XCTUnwrap(SheetImport.addCards([Row(front: "a", back: "b")], to: deck, in: context).first)
        XCTAssertFalse(card.frontLined)
        XCTAssertTrue(card.backLined)
    }

    func testImportCanBeUndone() throws {
        let context = try makeContext()
        let deck = Deck(title: "D")
        context.insert(deck)
        let existing = deck.newCard()
        let added = SheetImport.addCards([Row(front: "a", back: "b"), Row(front: "c", back: "d")], to: deck, in: context)
        SheetImport.offerUndo(added, in: deck, context: context)

        UndoCenter.shared.perform()

        XCTAssertEqual(deck.liveCards.count, 1)
        XCTAssertTrue(deck.liveCards[0] === existing)
        XCTAssertEqual(existing.order, 0)
    }

    func testLongTextGetsASmallerFont() {
        XCTAssertGreaterThan(SheetImport.fontSize(for: "short"), SheetImport.fontSize(for: String(repeating: "x", count: 300)))
        XCTAssertGreaterThan(SheetImport.fontSize(for: String(repeating: "x", count: 300)),
                             SheetImport.fontSize(for: String(repeating: "x", count: 1200)))
    }

    // MARK: New card paper

    func testNewCardsHaveBlankFrontAndLinedBack() throws {
        let context = try makeContext()
        let deck = Deck(title: "D")
        context.insert(deck)
        let card = deck.newCard()
        XCTAssertFalse(card.isLined(.front))
        XCTAssertTrue(card.isLined(.back))
    }

    func testDuplicatedCardsKeepTheirOwnPaper() throws {
        let context = try makeContext()
        let deck = Deck(title: "D")
        context.insert(deck)
        let card = deck.newCard()
        card.frontLined = true      // the person turned lines on for the front
        card.backLined = false
        let copy = card.contentCopy(order: 1)
        XCTAssertTrue(copy.frontLined)
        XCTAssertFalse(copy.backLined)
    }

    // MARK: PDF

    func testPDFHasAFrontAndBackPagePerCard() async throws {
        let context = try makeContext()
        let deck = Deck(title: "Bio/Chapter 1")
        context.insert(deck)
        SheetImport.addCards([Row(front: "a", back: "b"), Row(front: "c", back: "d")], to: deck, in: context)

        let url = try await PDFExport.export(deck)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 4)
    }

    func testPDFOfAnEmptyDeckIsAnError() async throws {
        let context = try makeContext()
        let deck = Deck(title: "Empty")
        context.insert(deck)
        do {
            _ = try await PDFExport.export(deck)
            XCTFail("An empty deck should not export")
        } catch {
            XCTAssertEqual(error as? PDFExport.PDFError, .noCards)
        }
    }
}
