import XCTest
import SwiftData
@testable import apple_flash_card

@MainActor
final class SpreadsheetTests: XCTestCase {
    func testCSVWithHeaderAndQuotes() throws {
        let csv = "Term,Definition\nCat,\"A small, furry animal\"\n\"Say \"\"hi\"\"\",Greeting\n\n"
        let t = try SpreadsheetParser.parse(Data(csv.utf8), fileExtension: "csv")
        XCTAssertEqual(t.headers, ["Term", "Definition"])
        XCTAssertEqual(t.rows, [["Cat", "A small, furry animal"], ["Say \"hi\"", "Greeting"]])
    }

    func testSemicolonAndCRLFAndMissingSecondColumn() throws {
        let csv = "Front;Back\r\nA;B\r\nOnlyFront\r\n"
        let t = try SpreadsheetParser.parse(Data(csv.utf8), fileExtension: "csv")
        XCTAssertEqual(t.rows, [["A", "B"], ["OnlyFront", ""]])
    }

    func testHeaderOnlyIsEmpty() {
        XCTAssertThrowsError(try SpreadsheetParser.parse(Data("A,B\n".utf8), fileExtension: "csv")) {
            XCTAssertEqual($0 as? SpreadsheetError, .empty)
        }
    }

    func testGarbageZipIsUnreadable() {
        let junk = Data([0x50, 0x4B] + Array(repeating: UInt8(7), count: 40))
        XCTAssertThrowsError(try SpreadsheetParser.parse(junk, fileExtension: "xlsx"))
    }

    func testLayoutCentersAndSizesText() {
        let long = "A long answer " + String(repeating: "x", count: 200)
        let items = SpreadsheetCardLayout.items(front: "Cat", back: long, headers: ["Term", "Meaning"])
        XCTAssertEqual(items.count, 4)
        XCTAssertTrue(items.allSatisfy { $0.centered == true })
        let frontBody = items.first { $0.side == 0 && $0.text == "Cat" }!
        let backBody = items.first { $0.side == 1 && $0.text.hasPrefix("A long") }!
        XCTAssertGreaterThan(frontBody.size, backBody.size)
        XCTAssertGreaterThanOrEqual(backBody.size, 0.026)
        XCTAssertTrue(items.allSatisfy { $0.y >= 0.04 && $0.y <= 0.7 })
    }

    func testBuildCreatesCardsInOrderWithHeaders() throws {
        let context = ModelContext(try AppStore_.makeContainer(inMemory: true))
        let table = SpreadsheetTable(headers: ["Term", "Meaning"], rows: [["a", "1"], ["b", "2"]])
        let deck = SpreadsheetImporter.build(table, title: "T", in: context)
        let cards = deck.sortedCards
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].textItems(.front).map(\.text).sorted(), ["Term", "a"])
        XCTAssertEqual(cards[1].textItems(.back).map(\.text).sorted(), ["2", "Meaning"])
    }

    func testRealXLSX() throws {
        let data = Data(base64Encoded: "UEsDBBQAAAAIANdlUF3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgA12VQXZoveHtLAAAAgwAAABQAAAB4bC9zaGFyZWRTdHJpbmdzLnhtbLMpLi6xsynOtLMpsQtJLcq10Qdy9UF8iJhvamJeZl46qnARSMYjNQciWgQVyMmH85EMcC9KTS0BmqCglphbYK2Qm1+UijBMH2Q7AFBLAwQUAAAACADXZVBdQTLQtGUAAADoAAAAGAAAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbLMpzy/KLs5ITS2xswFTLokliXY2RfnlCkW2SoZKdjbJIIajoZJCia1SMZBfZmdgo19mZ6OfDJVzQpYzhMvpA82AG2QEN8gISbERmkHIcsbYDTKGGeRkDFZmYoSmTh/JF/oIzwEAUEsBAhQDFAAAAAgA12VQXcccFzwKAAAACAAAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACADXZVBdmi94e0sAAACDAAAAFAAAAAAAAAAAAAAAgAE7AAAAeGwvc2hhcmVkU3RyaW5ncy54bWxQSwECFAMUAAAACADXZVBdQTLQtGUAAADoAAAAGAAAAAAAAAAAAAAAgAG4AAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sUEsFBgAAAAADAAMAyQAAAFMBAAAAAA==")!
        let t = try SpreadsheetParser.parse(data, fileExtension: "xlsx")
        XCTAssertEqual(t.headers, ["Term", "Meaning"])
        XCTAssertEqual(t.rows, [["Hello", "Greeting & more"], ["", "42"]])
    }
}
