import Foundation
import Combine

/// What happened on one calendar day.
nonisolated struct DayStat: Codable, Equatable, Sendable {
    var reviewed = 0
    var correct = 0
    var seconds = 0.0
}

/// A per-day record of studying, used for the streak and the stats screen. It lives in
/// UserDefaults rather than the card database so it survives deleting decks and needs
/// no store migration.
@MainActor final class StudyLog: ObservableObject {
    static let shared = StudyLog()

    @Published private(set) var days: [String: DayStat] = [:]
    private let storageKey = "studyLog.v1"
    private let calendar: Calendar
    private let defaults: UserDefaults

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// `defaults` and `calendar` are injectable so tests can use a throwaway store and fixed days.
    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: DayStat].self, from: data) {
            days = decoded
        }
    }

    // MARK: Recording

    func record(known: Bool, seconds: Double, on date: Date = .now) {
        var stat = days[key(date)] ?? DayStat()
        stat.reviewed += 1
        if known { stat.correct += 1 }
        stat.seconds += seconds
        days[key(date)] = stat
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: Reading

    func stat(on date: Date) -> DayStat { days[key(date)] ?? DayStat() }
    var today: DayStat { stat(on: .now) }
    var studiedToday: Bool { today.reviewed > 0 }
    func studied(on date: Date) -> Bool { stat(on: date).reviewed > 0 }

    var currentStreak: Int { streak(asOf: .now) }

    /// Consecutive days with at least one review, counted back from `now`. A streak is still
    /// alive if you haven't studied yet today but did yesterday.
    func streak(asOf now: Date) -> Int {
        var day = calendar.startOfDay(for: now)
        if !studied(on: day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while studied(on: day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    var bestStreak: Int {
        let dates = days.keys.compactMap { Self.formatter.date(from: $0) }.sorted()
        var best = 0, run = 0
        var previous: Date?
        for date in dates {
            if let p = previous, calendar.dateComponents([.day], from: p, to: date).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = date
        }
        return best
    }

    var totalReviewed: Int { days.values.reduce(0) { $0 + $1.reviewed } }
    var totalCorrect: Int { days.values.reduce(0) { $0 + $1.correct } }
    var totalSeconds: Double { days.values.reduce(0) { $0 + $1.seconds } }
    var daysStudied: Int { days.values.filter { $0.reviewed > 0 }.count }
    var accuracy: Double { totalReviewed == 0 ? 0 : Double(totalCorrect) / Double(totalReviewed) }

    /// The last `count` days ending today, oldest first.
    func recent(_ count: Int) -> [(date: Date, stat: DayStat)] {
        let start = calendar.startOfDay(for: .now)
        return (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: start)!
            return (date, stat(on: date))
        }
    }

    private func key(_ date: Date) -> String {
        Self.formatter.timeZone = calendar.timeZone
        return Self.formatter.string(from: date)
    }
}
