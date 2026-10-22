import XCTest
import PencilKit
import SwiftData
@testable import apple_flash_card

/// Builds pen strokes that trace a word in a handwriting-style font and runs them through the
/// real reader, to check that recognition works end to end.
final class RecognitionSmokeTests: XCTestCase {
    static func drawing(word: String, fontName: String = "Noteworthy-Bold", size: CGFloat = 120) -> PKDrawing {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        var glyphs = [CGGlyph](repeating: 0, count: word.utf16.count)
        var chars = Array(word.utf16)
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, glyphs.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .default, glyphs, &advances, glyphs.count)
        var strokes: [PKStroke] = []
        var x: CGFloat = 40
        for (g, adv) in zip(glyphs, advances) {
            if let path = CTFontCreatePathForGlyph(font, g, nil) {
                var current: [PKStrokePoint] = []
                func flush() {
                    if current.count > 1 {
                        strokes.append(PKStroke(ink: PKInk(.pen, color: .black),
                                                path: PKStrokePath(controlPoints: current, creationDate: Date())))
                    }
                    current = []
                }
                var t = 0.0
                func add(_ p: CGPoint) {
                    let loc = CGPoint(x: x + p.x, y: 200 - p.y)
                    current.append(PKStrokePoint(location: loc, timeOffset: t, size: CGSize(width: 4, height: 4),
                                                 opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
                    t += 0.01
                }
                var last = CGPoint.zero
                path.applyWithBlock { e in
                    let p = e.pointee.points
                    switch e.pointee.type {
                    case .moveToPoint: flush(); add(p[0]); last = p[0]
                    case .addLineToPoint: add(p[0]); last = p[0]
                    case .addQuadCurveToPoint:
                        for i in 1...6 { let u = CGFloat(i) / 6
                            add(CGPoint(x: (1-u)*(1-u)*last.x + 2*(1-u)*u*p[0].x + u*u*p[1].x,
                                        y: (1-u)*(1-u)*last.y + 2*(1-u)*u*p[0].y + u*u*p[1].y)) }
                        last = p[1]
                    case .addCurveToPoint:
                        for i in 1...8 { let u = CGFloat(i) / 8
                            let a = (1-u)*(1-u)*(1-u), b = 3*(1-u)*(1-u)*u, c = 3*(1-u)*u*u, d = u*u*u
                            add(CGPoint(x: a*last.x + b*p[0].x + c*p[1].x + d*p[2].x,
                                        y: a*last.y + b*p[0].y + c*p[1].y + d*p[2].y)) }
                        last = p[2]
                    case .closeSubpath: flush()
                    @unknown default: break
                    }
                }
                flush()
            }
            x += adv.width
        }
        return PKDrawing(strokes: strokes)
    }

    func testReaderReadsAHandwritingStyleWord() async throws {
        let drawing = Self.drawing(word: "distal")
        XCTAssertFalse(drawing.strokes.isEmpty)
        let text = await HandwritingIndex.recognize(drawing.dataRepresentation())
        print("RECOGNISED:", text)
        XCTAssertTrue(CardSearch.handwritingMatches(text, "dis"), "read as: \(text)")
    }

    @MainActor
    func testIndexingThenSearchingFindsPartialWord() async throws {
        let context = ModelContext(try AppStore_.makeContainer(inMemory: true))
        let deck = Deck(title: "Anatomy"); context.insert(deck)
        let card = deck.newCard()
        card.front = Self.drawing(word: "distal").dataRepresentation()
        let other = deck.newCard()
        other.front = Self.drawing(word: "lateral").dataRepresentation()
        try context.save()

        await HandwritingIndex.indexAll(in: context)

        XCTAssertFalse(card.frontInkText.isEmpty, "nothing was read")
        let hits = CardSearch.run("dis", in: [deck])
        XCTAssertEqual(hits.count, 1, "read as: \(card.frontInkText) / \(other.frontInkText)")
        XCTAssertTrue(hits.first?.card === card)
        XCTAssertEqual(hits.first?.readAs?.isEmpty, false)
    }
}

extension RecognitionSmokeTests {
    func testTwoLinesAreSplitAndBothRead() async throws {
        var all = Self.drawing(word: "distal").strokes
        let lower = Self.drawing(word: "lateral").strokes.map { s -> PKStroke in
            var t = s; t.transform = CGAffineTransform(translationX: 0, y: 220); return t
        }
        all += lower
        let drawing = PKDrawing(strokes: all)
        XCTAssertEqual(HandwritingIndex.lineClusters(drawing).count, 2)
        let text = await HandwritingIndex.recognize(drawing.dataRepresentation())
        print("RECOGNISED2:", text)
        XCTAssertTrue(CardSearch.handwritingMatches(text, "dis"), text)
        XCTAssertTrue(CardSearch.handwritingMatches(text, "lateral"), text)
    }
}

extension RecognitionSmokeTests {
    private static func swipe(ink: PKInk, from a: CGPoint, to b: CGPoint, width: CGFloat) -> PKStroke {
        let pts = (0...10).map { i -> PKStrokePoint in
            let u = CGFloat(i) / 10
            return PKStrokePoint(location: CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u),
                                 timeOffset: Double(i) * 0.02, size: CGSize(width: width, height: width),
                                 opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: Date()))
    }

    func testHighlighterAndYellowArrowsDoNotHideTheWords() async throws {
        var strokes = Self.drawing(word: "distal").strokes
        let bounds = PKDrawing(strokes: strokes).bounds
        // A thick yellow highlighter swipe right through the middle of the word...
        strokes.append(Self.swipe(ink: PKInk(.marker, color: UIColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)),
                                  from: CGPoint(x: bounds.minX, y: bounds.midY), to: CGPoint(x: bounds.maxX, y: bounds.midY),
                                  width: bounds.height * 0.6))
        // ...and a yellow pen line (like an arrow) across it.
        strokes.append(Self.swipe(ink: PKInk(.pen, color: UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)),
                                  from: CGPoint(x: bounds.minX, y: bounds.minY), to: CGPoint(x: bounds.maxX, y: bounds.maxY),
                                  width: 6))
        let text = await HandwritingIndex.recognize(PKDrawing(strokes: strokes).dataRepresentation())
        print("RECOGNISED3:", text)
        XCTAssertTrue(CardSearch.handwritingMatches(text, "dis"), text)
    }
}

@MainActor
final class InkWidthTests: XCTestCase {
    private func withLastKnown(_ value: Double, _ body: () throws -> Void) rethrows {
        let old = Card.lastKnownCardWidth
        Card.lastKnownCardWidth = value
        defer { Card.lastKnownCardWidth = old }
        try body()
    }

    func testRecordedWidthWinsThenLastKnownThenDefault() {
        let card = Card(order: 0)
        withLastKnown(0) { XCTAssertEqual(card.effectiveInkWidth, Card.defaultCardWidth) }
        withLastKnown(950) { XCTAssertEqual(card.effectiveInkWidth, 950) }
        card.inkRefWidth = 700
        withLastKnown(950) { XCTAssertEqual(card.effectiveInkWidth, 700) }
    }

    func testBackupFillsInTheWidthForCardsThatNeverRecordedOne() throws {
        let context = ModelContext(try AppStore_.makeContainer(inMemory: true))
        let deck = Deck(title: "Old"); context.insert(deck)
        let withInk = deck.newCard()
        withInk.front = RecognitionSmokeTests.drawing(word: "distal").dataRepresentation()
        let blank = deck.newCard()
        withLastKnown(912) {
            XCTAssertEqual(withInk.backupInkWidth, 912)
            XCTAssertNil(blank.backupInkWidth)                       // nothing drawn, nothing to place
        }
        withLastKnown(0) { XCTAssertNil(withInk.backupInkWidth) }     // nothing known: leave it unset
        withInk.inkRefWidth = 640
        withLastKnown(912) { XCTAssertEqual(withInk.backupInkWidth, 640) }
    }
}
