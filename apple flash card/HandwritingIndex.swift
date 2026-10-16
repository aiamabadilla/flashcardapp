import SwiftUI
import SwiftData
import PencilKit
import Vision
import CryptoKit

/// Reads the handwriting on each card side with Apple's Vision framework and stores the
/// recognised text on the card, so search can find cards by what you wrote. A side is
/// only read again after its ink changes.
enum HandwritingIndex {
    private nonisolated static let emptyMarker = "empty"

    /// Bump when the reading method improves, so cards are read again with the new method.
    private nonisolated static let methodVersion = "v6"

    /// A short, stable fingerprint of a drawing's bytes (and of the reading method).
    nonisolated static func fingerprint(_ data: Data) -> String {
        guard !data.isEmpty else { return emptyMarker }
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(methodVersion)-\(digest)"
    }

    /// How a drawing is prepared for reading. Real handwriting is thin and small compared to
    /// what text recognition expects, so strokes are thickened, drawn large and padded.
    private nonisolated struct Pass {
        let thicknessDivisor: CGFloat   // minimum stroke width = writing height / this
        let targetSide: CGFloat         // longest side of the image, in pixels
        let paddingFactor: CGFloat      // blank border, as a multiple of the writing height
    }

    // Real handwriting (checked against a student's cards) is read best with the plain strokes,
    // so that is tried first. Mild and heavy thickening are fallbacks for very fine or faint
    // writing. Results are combined, which suits search: a word found by any pass counts.
    private nonisolated static let plain = Pass(thicknessDivisor: 0, targetSide: 2000, paddingFactor: 1.0)
    private nonisolated static let mild = Pass(thicknessDivisor: 40, targetSide: 2000, paddingFactor: 1.5)
    private nonisolated static let heavy = Pass(thicknessDivisor: 12, targetSide: 1600, paddingFactor: 1.0)
    private nonisolated static let linePasses = [plain, mild]
    private nonisolated static let wholePasses = [plain, heavy]

    /// Highlighter strokes and yellow pen marks (arrows, brackets) aren't writing, and drawn as
    /// solid black they would cover the words they mark.
    private nonisolated static func isWriting(_ stroke: PKStroke) -> Bool {
        if stroke.ink.inkType == .marker { return false }
        let color = stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var hue: CGFloat = 0, sat: CGFloat = 0, bright: CGFloat = 0, alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha) else { return true }
        let yellowish = hue > 0.08 && hue < 0.2 && sat > 0.35 && bright > 0.75
        return !yellowish
    }

    /// The same strokes with a minimum width, drawn in plain black.
    private nonisolated static func thickened(_ drawing: PKDrawing, minimumWidth: CGFloat) -> PKDrawing {
        let strokes = drawing.strokes.filter(isWriting).map { stroke -> PKStroke in
            let points = stroke.path.map { p in
                let w = max(p.size.width, minimumWidth)   // minimumWidth 0 keeps the strokes as drawn
                return PKStrokePoint(location: p.location, timeOffset: p.timeOffset,
                                     size: CGSize(width: w, height: w), opacity: 1,
                                     force: p.force, azimuth: p.azimuth, altitude: p.altitude)
            }
            return PKStroke(ink: PKInk(.pen, color: .black),
                            path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate))
        }
        return PKDrawing(strokes: strokes)
    }

    private nonisolated static func read(_ drawing: PKDrawing, pass: Pass, customWords: [String]) -> String {
        let height = max(drawing.bounds.height, 1)
        let long = max(drawing.bounds.width, height)
        let scale = min(max(pass.targetSide / long, 1), 8)
        let minimumWidth = pass.thicknessDivisor > 0 ? max(1.5, height / pass.thicknessDivisor) : 0
        let source = thickened(drawing, minimumWidth: minimumWidth)
        guard !source.bounds.isEmpty else { return "" }
        let bounds = source.bounds.insetBy(dx: -max(24, height * pass.paddingFactor),
                                           dy: -max(24, height * pass.paddingFactor))

        // Vision reads dark text on a light background, so draw the ink on white.
        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = source.image(from: bounds, scale: scale)
        }
        guard let ink else { return "" }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let flattened = UIGraphicsImageRenderer(size: ink.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: ink.size))
            ink.draw(at: .zero)
        }
        guard let cgImage = flattened.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        // Terms from the person's own cards (e.g. "carcin", "cephal") that language correction
        // would otherwise turn into ordinary English words.
        if !customWords.isEmpty { request.customWords = customWords }
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        // For search, every plausible reading counts: take the top few candidates of each line.
        return (request.results ?? [])
            .flatMap { $0.topCandidates(3).map(\.string) }
            .joined(separator: " ")
    }

    /// Splits a drawing into lines of writing: strokes that share a vertical band belong together.
    nonisolated static func lineClusters(_ drawing: PKDrawing, limit: Int = 8) -> [PKDrawing] {
        let strokes = drawing.strokes.filter(isWriting)
        guard strokes.count > 1 else { return [] }
        var groups: [(range: ClosedRange<CGFloat>, strokes: [PKStroke])] = []
        for stroke in strokes {
            let b = stroke.renderBounds
            let range = b.minY...max(b.maxY, b.minY + 1)
            if let i = groups.firstIndex(where: { $0.range.overlaps(range) }) {
                groups[i].strokes.append(stroke)
                groups[i].range = min(groups[i].range.lowerBound, range.lowerBound)...max(groups[i].range.upperBound, range.upperBound)
            } else {
                groups.append((range, [stroke]))
            }
        }
        // A stroke can bridge two groups that started apart (the dot of an "i", a tall letter).
        var merged = true
        while merged {
            merged = false
            outer: for i in groups.indices {
                for j in groups.indices where j > i && groups[i].range.overlaps(groups[j].range) {
                    groups[i].strokes += groups[j].strokes
                    groups[i].range = min(groups[i].range.lowerBound, groups[j].range.lowerBound)...max(groups[i].range.upperBound, groups[j].range.upperBound)
                    groups.remove(at: j)
                    merged = true
                    break outer
                }
            }
        }
        guard groups.count > 1 else { return [] }       // one line: the whole-drawing pass covers it
        return groups.sorted { $0.range.lowerBound < $1.range.lowerBound }
            .prefix(limit).map { PKDrawing(strokes: $0.strokes) }
    }

    /// Reads the text in a saved drawing. Runs off the main thread.
    static func recognize(_ data: Data, customWords: [String] = []) async -> String {
        await Task.detached(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return "" }
            // Each line of writing on its own (small words get lost when a whole card is read at
            // once), then the whole drawing. The plain reading comes first; thicker fallbacks are
            // only tried when it finds nothing, which keeps reading a big deck quick.
            func firstReading(_ d: PKDrawing, _ passes: [Pass]) -> String {
                for pass in passes {
                    let text = read(d, pass: pass, customWords: customWords)
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
                }
                return ""
            }
            let lines = lineClusters(drawing).map { firstReading($0, linePasses) }
            let whole = firstReading(drawing, wholePasses)
            return (lines + [whole]).joined(separator: " ")
        }.value
    }

    /// Words worth teaching the recogniser: the distinct words of the typed text on the person's
    /// cards, most common first. Short words are left out because ordinary English already
    /// covers them. English only.
    nonisolated static func vocabulary(from texts: [String], limit: Int = 800) -> [String] {
        var counts: [String: Int] = [:]
        for text in texts {
            for word in CardSearch.tokens(text) where word.count >= 4 && word.count <= 24
                && word.unicodeScalars.allSatisfy({ $0.isASCII }) && !word.allSatisfy(\.isNumber) {
                counts[word, default: 0] += 1
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit).map(\.key)
    }

    /// One side of one card, as plain values so it can be hashed and read off the main thread.
    private struct Job: Sendable {
        let id: PersistentIdentifier
        let side: Int            // 0 = front, 1 = back
        let data: Data
        let knownHash: String
    }

    /// Reads every side that is new or changed. `progress` reports how many are left.
    /// Hashing and recognition happen off the main thread; only the results are applied on it.
    @MainActor static func indexAll(in context: ModelContext, progress: ((Int) -> Void)? = nil) async {
        // Launch, search and the editor closing can all ask at once; run one pass at a time per
        // store and go round again if something was asked for meanwhile.
        let key = ObjectIdentifier(context)
        if running.contains(key) {
            // Already reading: ask for another round, and return once everything is read.
            rerun.insert(key)
            while running.contains(key) { try? await Task.sleep(for: .milliseconds(50)) }
            return
        }
        running.insert(key)
        defer { running.remove(key) }
        repeat {
            rerun.remove(key)
            await indexPass(in: context, progress: progress)
        } while rerun.contains(key)
    }

    @MainActor private static var running: Set<ObjectIdentifier> = []
    @MainActor private static var rerun: Set<ObjectIdentifier> = []

    @MainActor private static func indexPass(in context: ModelContext, progress: ((Int) -> Void)?) async {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        var jobs: [Job] = []
        for card in cards where card.deletedAt == 0 {
            jobs.append(Job(id: card.persistentModelID, side: 0, data: card.front, knownHash: card.frontInkHash))
            jobs.append(Job(id: card.persistentModelID, side: 1, data: card.back, knownHash: card.backInkHash))
        }

        // Which sides changed? (hashes every drawing, so not on the main thread)
        let dirty: [(job: Job, hash: String)] = await Task.detached(priority: .utility) {
            jobs.compactMap { job in
                let hash = fingerprint(job.data)
                return hash == job.knownHash ? nil : (job, hash)
            }
        }.value

        var left = dirty.count
        progress?(left)
        guard left > 0 else { return }

        let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.persistentModelID, $0) })
        let words = vocabulary(from: cards.filter { $0.deletedAt == 0 }.flatMap { $0.allTextItems.map(\.text) })
        for item in dirty {
            let text = item.job.data.isEmpty ? "" : await recognize(item.job.data, customWords: words)
            if let card = byID[item.job.id] {
                card.setInk(text: text, hash: item.hash, item.job.side == 0 ? .front : .back)
            }
            left -= 1
            progress?(max(left, 0))
        }
        context.saveReporting("handwriting index")
    }
}

extension Card {
    func inkText(_ side: Side) -> String { side == .front ? frontInkText : backInkText }
    func inkHash(_ side: Side) -> String { side == .front ? frontInkHash : backInkHash }

    func setInk(text: String, hash: String, _ side: Side) {
        if side == .front { frontInkText = text; frontInkHash = hash }
        else { backInkText = text; backInkHash = hash }
    }
}

// MARK: - Searching

struct SearchHit: Identifiable {
    let card: Card
    let deck: Deck
    /// Where the words were found, e.g. "Front · handwriting".
    let matches: [String]
    /// What the app read from the handwriting (so a misread is easy to see), if it matched there.
    var readAs: String? {
        guard matches.contains(where: { $0.hasSuffix("handwriting") }) else { return nil }
        let text = [card.frontInkText, card.backInkText].joined(separator: " ")
        let words = Array(NSOrderedSet(array: text.split(separator: " ").map(String.init))) as? [String] ?? []
        return words.prefix(12).joined(separator: " ")
    }
    var id: PersistentIdentifier { card.persistentModelID }
}

enum CardSearch {
    /// Which parts of a card match the query ("Front · typed text", "Back · handwriting"...).
    static func matches(_ card: Card, _ query: String) -> [String] {
        var found: [String] = []
        for side in [Side.front, .back] {
            let name = side == .front ? "Front" : "Back"
            let typed = card.textItems(side).map(\.text).joined(separator: " ")
            if typed.localizedStandardContains(query) { found.append("\(name) · typed text") }
            if handwritingMatches(card.inkText(side), query) { found.append("\(name) · handwriting") }
        }
        return found
    }

    static func run(_ query: String, in decks: [Deck]) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for deck in decks {
            for card in deck.sortedCards {
                let found = matches(card, q)
                if !found.isEmpty { hits.append(SearchHit(card: card, deck: deck, matches: found)) }
            }
        }
        return hits
    }

    // MARK: Handwriting matching

    /// Recognised handwriting is rarely perfect, so every word of the query must appear in the
    /// text exactly, as part of a word, or (for longer words) within a letter or two of a word.
    nonisolated static func handwritingMatches(_ text: String, _ query: String) -> Bool {
        let raw = tokens(text)
        let wanted = tokens(query)
        guard !wanted.isEmpty, !raw.isEmpty else { return false }
        // Also compare with look-alike letters merged ("cl" read for "d", "l" for "i", ...), so a
        // misread that changes the shape of the word still matches.
        let rawWords = raw
        let skeletonWords = raw.map(skeleton)
        let skeletonWanted = wanted.map(skeleton)
        func every(_ targets: [String], in words: [String]) -> Bool {
            targets.allSatisfy { target in words.contains { wordMatches($0, target) } }
        }
        return every(wanted, in: rawWords) || every(skeletonWanted, in: skeletonWords)
    }

    private nonisolated static func wordMatches(_ word: String, _ target: String) -> Bool {
        if word.contains(target) { return true }
        let allowed = target.count >= 8 ? 2 : (target.count >= 4 ? 1 : 0)
        guard allowed > 0 else { return false }
        // Compare against the word, and against a same-length slice of a longer word.
        if abs(word.count - target.count) <= allowed,
           editDistance(Array(word), Array(target), limit: allowed) <= allowed { return true }
        if word.count > target.count {
            let chars = Array(word)
            for start in 0...(chars.count - target.count) {
                let slice = Array(chars[start..<(start + target.count)])
                if editDistance(slice, Array(target), limit: allowed) <= allowed { return true }
            }
        }
        return false
    }

    /// Letters handwriting recognition commonly confuses, merged into one form.
    nonisolated static func skeleton(_ word: String) -> String {
        var s = word
        for (from, to) in [("cl", "d"), ("rn", "m"), ("vv", "w"), ("ii", "u")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return String(s.map { c -> Character in
            switch c {
            case "l", "1", "j": "i"
            case "0": "o"
            case "5": "s"
            case "q": "g"
            default: c
            }
        })
    }

    nonisolated static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Levenshtein distance, giving up (returning limit + 1) once it must exceed `limit`.
    nonisolated static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if a == b { return 0 }
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where i <= a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            var rowMin = current[0]
            for j in 1...max(b.count, 1) where j <= b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }
}

struct SearchTarget: Identifiable {
    let id = UUID()
    let deck: Deck
    let card: Card
}

/// The results shown while the search field has text.
struct SearchResultsView: View {
    let query: String
    let decks: [Deck]
    let indexingLeft: Int
    let onOpen: (SearchHit) -> Void

    var body: some View {
        let hits = CardSearch.run(query, in: decks)
        let deckHits = decks.filter { $0.title.localizedStandardContains(query) }

        List {
            if indexingLeft > 0 {
                Label("Reading handwriting… \(indexingLeft) left", systemImage: "pencil.and.scribble")
                    .foregroundStyle(.secondary)
            }
            if !deckHits.isEmpty {
                Section("Decks") {
                    ForEach(deckHits) { deck in
                        Text(deck.displayTitle)
                    }
                }
            }
            if !hits.isEmpty {
                Section("Cards") {
                    ForEach(hits) { hit in
                        Button { Haptics.tap(); onOpen(hit) } label: {
                            HStack(spacing: 16) {
                                CardFace(card: hit.card, side: .front, corner: 8, inset: 6)
                                    .frame(width: 130)
                                    .shadow(radius: 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.deck.displayTitle).font(.headline)
                                    ForEach(hit.matches, id: \.self) {
                                        Text($0).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    if let read = hit.readAs {
                                        Text("Read as: \(read)").font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if hits.isEmpty && deckHits.isEmpty && indexingLeft == 0 {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
