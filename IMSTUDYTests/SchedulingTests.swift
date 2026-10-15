import XCTest
@testable import apple_flash_card

@MainActor
final class SchedulingTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNewCardIsNewAndDue() {
        let card = Card(order: 0)
        XCTAssertTrue(card.isNew)
        XCTAssertTrue(card.isDue)
        XCTAssertFalse(card.isMastered)
    }

    func testKnowingMovesUpABoxAndSpacesTheNextReview() {
        let card = Card(order: 0)
        let expectedDays: [Double] = [1, 2, 4, 8, 16]   // boxes 1...5
        for (i, days) in expectedDays.enumerated() {
            card.review(known: true, now: now)
            XCTAssertEqual(card.leitnerBox, i + 1)
            XCTAssertEqual(card.dueTime, now.timeIntervalSince1970 + days * day, accuracy: 1)
        }
    }

    func testTopBoxStaysAtTopAndKeepsLongestInterval() {
        let card = Card(order: 0)
        for _ in 0..<10 { card.review(known: true, now: now) }
        XCTAssertEqual(card.leitnerBox, 5)
        XCTAssertEqual(card.dueTime, now.timeIntervalSince1970 + 16 * day, accuracy: 1)
    }

    func testMissingSendsCardBackToBoxZeroAndDueNow() {
        let card = Card(order: 0)
        card.review(known: true, now: now)
        card.review(known: true, now: now)
        card.review(known: false, now: now)
        XCTAssertEqual(card.leitnerBox, 0)
        XCTAssertEqual(card.dueTime, now.timeIntervalSince1970, accuracy: 1)
    }

    func testCountsTrackAnswers() {
        let card = Card(order: 0)
        card.review(known: true, now: now)
        card.review(known: false, now: now)
        card.review(known: true, now: now)
        XCTAssertEqual(card.reviewCount, 3)
        XCTAssertEqual(card.correctCount, 2)
        XCTAssertEqual(card.lastReviewed, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertFalse(card.isNew)
    }

    func testMasteredFromBoxFour() {
        let card = Card(order: 0)
        for _ in 0..<4 { card.review(known: true, now: now) }
        XCTAssertTrue(card.isMastered)
    }

    func testDeckDueCardsExcludeFutureAndTrashed() {
        let deck = Deck(title: "D")
        let due = deck.newCard()
        let later = deck.newCard()
        later.review(known: true)               // due tomorrow
        let trashed = deck.newCard()
        trashed.deletedAt = Date().timeIntervalSince1970
        XCTAssertEqual(deck.dueCards.map { ObjectIdentifier($0) }, [ObjectIdentifier(due)])
        XCTAssertFalse(deck.dueCards.contains { $0 === trashed })
        XCTAssertFalse(deck.dueCards.contains { $0 === later })
    }

    func testNewCardGoesFirstAndShiftsOthers() {
        let deck = Deck(title: "D")
        let first = deck.newCard()
        let second = deck.newCard()
        XCTAssertEqual(second.order, 0)
        XCTAssertEqual(first.order, 1)
        XCTAssertEqual(deck.sortedCards.first === second, true)
    }
}

@MainActor
final class StreakTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func makeLog() -> StudyLog {
        let suite = "imstudy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let log = StudyLog(defaults: defaults, calendar: calendar)
        _ = Unmanaged.passRetained(log)   // avoid a deinit crash on teardown; see testLogPersists
        return log
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testStreakCountsConsecutiveDays() {
        let log = makeLog()
        for d in 10...12 { log.record(known: true, seconds: 5, on: date(2026, 10, d)) }
        XCTAssertEqual(log.streak(asOf: date(2026, 10, 12)), 3)
    }

    func testStreakSurvivesUntilEndOfTodayIfYesterdayWasStudied() {
        let log = makeLog()
        log.record(known: true, seconds: 5, on: date(2026, 10, 11))
        log.record(known: true, seconds: 5, on: date(2026, 10, 12))
        XCTAssertEqual(log.streak(asOf: date(2026, 10, 13)), 2, "not studied yet today, still alive")
    }

    func testStreakBreaksAfterAMissedDay() {
        let log = makeLog()
        log.record(known: true, seconds: 5, on: date(2026, 10, 10))
        XCTAssertEqual(log.streak(asOf: date(2026, 10, 12)), 0)
    }

    func testGapSplitsStreakAndBestStreakIsRemembered() {
        let log = makeLog()
        for d in [1, 2, 3, 4] { log.record(known: true, seconds: 5, on: date(2026, 10, d)) }
        for d in [7, 8] { log.record(known: true, seconds: 5, on: date(2026, 10, d)) }
        XCTAssertEqual(log.streak(asOf: date(2026, 10, 8)), 2)
        XCTAssertEqual(log.bestStreak, 4)
    }

    func testAccuracyAndTotals() {
        let log = makeLog()
        log.record(known: true, seconds: 10, on: date(2026, 10, 1))
        log.record(known: false, seconds: 20, on: date(2026, 10, 1))
        XCTAssertEqual(log.totalReviewed, 2)
        XCTAssertEqual(log.accuracy, 0.5, accuracy: 0.001)
        XCTAssertEqual(log.totalSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(log.daysStudied, 1)
    }

    func testLogPersistsAcrossInstances() {
        let suite = "imstudy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let first = StudyLog(defaults: defaults, calendar: calendar)
        first.record(known: true, seconds: 5, on: date(2026, 10, 5))
        let reloaded = StudyLog(defaults: defaults, calendar: calendar)
        _ = Unmanaged.passRetained(first)
        _ = Unmanaged.passRetained(reloaded)
        XCTAssertEqual(reloaded.totalReviewed, 1)
        defaults.removePersistentDomain(forName: suite)
    }
}
