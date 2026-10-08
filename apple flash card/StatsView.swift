import SwiftUI
import SwiftData
import Charts

/// The flame banner shown at the top of the deck list.
/// "1 day" / "2 days".
func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

struct StreakBanner: View {
    @ObservedObject private var log = StudyLog.shared

    var body: some View {
        let streak = log.currentStreak
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.system(size: 34))
                .foregroundStyle(log.studiedToday ? .orange : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(streak == 0 ? "No streak yet" : "\(plural(streak, "day")) streak")
                    .font(.title3.bold())
                Text(log.studiedToday
                     ? "\(plural(log.today.reviewed, "card")) reviewed today"
                     : (streak == 0 ? "Study a card to start one" : "Study today to keep it going"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chart.bar.xaxis").foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var log = StudyLog.shared
    @Query(filter: #Predicate<Deck> { $0.deletedAt == 0 }) private var decks: [Deck]
    private var cards: [Card] { decks.flatMap(\.liveCards) }
    @Environment(\.modelContext) private var context
    @State private var storageVersion = 0   // refreshes the storage numbers after a clean-up

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        Tile(title: "Current streak", value: "\(log.currentStreak)",
                             unit: unit(log.currentStreak, "day"), icon: "flame.fill", color: .orange)
                        Tile(title: "Best streak", value: "\(log.bestStreak)",
                             unit: unit(log.bestStreak, "day"), icon: "trophy.fill", color: .yellow)
                        Tile(title: "Reviewed today", value: "\(log.today.reviewed)",
                             unit: unit(log.today.reviewed, "card"), icon: "checkmark.circle.fill", color: .green)
                        Tile(title: "Due now", value: "\(cards.filter(\.isDue).count)",
                             unit: unit(cards.filter(\.isDue).count, "card"), icon: "clock.fill", color: .blue)
                        Tile(title: "Accuracy", value: percent(log.accuracy),
                             unit: "all time", icon: "target", color: .purple)
                        Tile(title: "Study time", value: duration(log.totalSeconds),
                             unit: "all time", icon: "timer", color: .teal)
                        Tile(title: "Total reviews", value: "\(log.totalReviewed)",
                             unit: unit(log.totalReviewed, "answer"), icon: "square.stack.fill", color: .indigo)
                        Tile(title: "Days studied", value: "\(log.daysStudied)",
                             unit: unit(log.daysStudied, "day"), icon: "calendar", color: .pink)
                    }

                    section("Last 7 days") { weekChart }
                    section("Your cards") { masteryChart }
                    section("Photo storage") { storage }
                }
                .padding(24)
            }
            .navigationTitle("Study Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Haptics.tap(); dismiss() }
                }
            }
        }
    }

    // MARK: Charts

    private var weekChart: some View {
        let week = log.recent(7)
        return Chart(week, id: \.date) { day in
            BarMark(x: .value("Day", day.date, unit: .day),
                    y: .value("Cards", day.stat.reviewed))
                .foregroundStyle(day.stat.reviewed > 0 ? Color.orange : Color.gray.opacity(0.3))
                .cornerRadius(5)
                .annotation(position: .top) {
                    if day.stat.reviewed > 0 { Text("\(day.stat.reviewed)").font(.caption) }
                }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .frame(height: 200)
    }

    private var masteryChart: some View {
        let groups: [(name: String, count: Int, color: Color)] = [
            ("New", cards.filter(\.isNew).count, .blue),
            ("Learning", cards.filter { !$0.isNew && $0.leitnerBox <= 1 }.count, .orange),
            ("Reviewing", cards.filter { !$0.isNew && ($0.leitnerBox == 2 || $0.leitnerBox == 3) }.count, .yellow),
            ("Mastered", cards.filter { !$0.isNew && $0.isMastered }.count, .green),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            if cards.isEmpty {
                Text("Add some cards to see your progress.").foregroundStyle(.secondary)
            } else {
                Chart(groups, id: \.name) { g in
                    BarMark(x: .value("Cards", g.count), y: .value("", "All cards"))
                        .foregroundStyle(g.color)
                }
                .chartXAxis(.hidden)
                .frame(height: 50)
                HStack(spacing: 18) {
                    ForEach(groups, id: \.name) { g in
                        HStack(spacing: 6) {
                            Circle().fill(g.color).frame(width: 10, height: 10)
                            Text("\(g.name) \(g.count)").font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    // MARK: Storage

    private var storage: some View {
        _ = storageVersion   // re-evaluate after a clean-up
        let files = ImageStore.storedFiles()
        let orphans = PhotoCleanup.unused(in: context)
        let total = files.reduce(0) { $0 + $1.bytes }
        let wasted = orphans.reduce(0) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(plural(files.count, "photo")) · \(bytes(total))")
            if orphans.isEmpty {
                Label("Nothing to clean up", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("\(plural(orphans.count, "unused photo")) taking up \(bytes(wasted)) " +
                     "(left over from deleted cards or photos)")
                    .foregroundStyle(.secondary)
                Button {
                    Haptics.success()
                    PhotoCleanup.run(in: context, force: true)
                    storageVersion += 1
                } label: {
                    Label("Clean Up", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func unit(_ n: Int, _ word: String) -> String { n == 1 ? word : word + "s" }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 34, weight: .bold, design: .rounded))
                Text(unit).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}
