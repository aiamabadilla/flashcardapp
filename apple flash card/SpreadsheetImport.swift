import Foundation
import Compression

/// A table read from a spreadsheet. Row 1 holds the column headers.
nonisolated struct SpreadsheetTable: Equatable, Sendable {
    var headers: [String]
    var rows: [[String]]
}

nonisolated enum SpreadsheetError: LocalizedError, Equatable {
    case unreadable
    case empty
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: "That file couldn't be read as a spreadsheet. Use a .xlsx or .csv file."
        case .empty: "The spreadsheet has no rows to import."
        case .tooLarge: "That spreadsheet is too large to import."
        }
    }
}

/// Reads .csv/.tsv and .xlsx using only system frameworks (no third-party code, no network).
nonisolated enum SpreadsheetParser {
    static let maxFileBytes = 10 * 1024 * 1024
    static let maxRows = 5000
    static let maxCellLength = 2000

    static func parse(_ data: Data, fileExtension: String) throws -> SpreadsheetTable {
        guard data.count <= maxFileBytes else { throw SpreadsheetError.tooLarge }
        let grid: [[String]]
        if fileExtension.lowercased() == "xlsx" || data.starts(with: [0x50, 0x4B]) {
            grid = try xlsxGrid(data)
        } else {
            grid = csvGrid(data)
        }
        return try table(from: grid)
    }

    /// Row 1 is the header; blank rows are skipped; only the first two columns are used.
    static func table(from grid: [[String]]) throws -> SpreadsheetTable {
        var rows = grid
            .map { row in row.prefix(2).map { String($0.prefix(maxCellLength)).trimmingCharacters(in: .whitespacesAndNewlines) } }
            .map { row -> [String] in
                var r = Array(row)
                while r.count < 2 { r.append("") }
                return r
            }
        guard let headers = rows.first else { throw SpreadsheetError.empty }
        rows.removeFirst()
        rows = rows.filter { !($0[0].isEmpty && $0[1].isEmpty) }
        guard !rows.isEmpty else { throw SpreadsheetError.empty }
        guard rows.count <= maxRows else { throw SpreadsheetError.tooLarge }
        return SpreadsheetTable(headers: headers, rows: rows)
    }

    // MARK: CSV

    static func csvGrid(_ data: Data) -> [[String]] {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        var delimiter: Character = ","
        var best = firstLine.filter { $0 == "," }.count
        for candidate in ["\t", ";"] as [Character] {
            let n = firstLine.filter { $0 == candidate }.count
            if n > best { best = n; delimiter = candidate }
        }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        return rows
    }

    // MARK: XLSX

    static func xlsxGrid(_ data: Data) throws -> [[String]] {
        guard let entries = ZipReader.entries(in: data) else { throw SpreadsheetError.unreadable }
        var strings: [String] = []
        if let shared = entries["xl/sharedStrings.xml"].flatMap({ ZipReader.read($0, from: data) }) {
            let p = SharedStringsParser()
            p.run(shared)
            strings = p.strings
        }
        let sheetName = entries.keys.contains("xl/worksheets/sheet1.xml")
            ? "xl/worksheets/sheet1.xml"
            : entries.keys.filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }.sorted().first
        guard let name = sheetName, let entry = entries[name],
              let xml = ZipReader.read(entry, from: data) else { throw SpreadsheetError.unreadable }
        let p = SheetParser(strings: strings)
        p.run(xml)
        return p.rows
    }
}

// MARK: - XML

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inText = false
    private var inItem = false

    func run(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "si" { inItem = true; current = "" }
        if name == "t", inItem { inText = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" { inText = false }
        if name == "si" { strings.append(current); inItem = false }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    var rows: [[String]] = []
    private let strings: [String]
    private var row: [Int: String] = [:]
    private var type = ""
    private var column = 0
    private var value = ""
    private var inValue = false

    init(strings: [String]) { self.strings = strings }

    func run(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    private static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for u in ref.uppercased().unicodeScalars where u.value >= 65 && u.value <= 90 {
            n = n * 26 + Int(u.value - 64)
        }
        return max(n - 1, 0)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "row": row = [:]
        case "c":
            type = attributes["t"] ?? ""
            column = attributes["r"].map(Self.columnIndex) ?? row.count
            value = ""
        case "v", "t": inValue = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { value += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t": inValue = false
        case "c":
            if type == "s", let i = Int(value.trimmingCharacters(in: .whitespaces)), strings.indices.contains(i) {
                row[column] = strings[i]
            } else {
                row[column] = value
            }
        case "row":
            let width = (row.keys.max() ?? -1) + 1
            rows.append((0..<width).map { row[$0] ?? "" })
        default: break
        }
    }
}

// MARK: - Minimal zip reader

/// Just enough of the zip format to read the XML parts of an .xlsx. Sizes are capped so a
/// crafted file can't expand into huge amounts of memory.
nonisolated enum ZipReader {
    struct Entry { let method: UInt16; let compressedSize: Int; let size: Int; let localOffset: Int }
    static let maxEntryBytes = 40 * 1024 * 1024

    private static func u16(_ d: Data, _ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
    private static func u32(_ d: Data, _ o: Int) -> Int { u16(d, o) | u16(d, o + 2) << 16 }

    static func entries(in data: Data) -> [String: Entry]? {
        guard data.count > 22 else { return nil }
        var eocd = -1
        var i = data.count - 22
        while i >= max(0, data.count - 22 - 65_535) {
            if u32(data, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let count = u16(data, eocd + 10)
        var offset = u32(data, eocd + 16)
        var result: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset + 46 <= data.count, u32(data, offset) == 0x02014b50 else { return nil }
            let method = UInt16(u16(data, offset + 10))
            let csize = u32(data, offset + 20)
            let size = u32(data, offset + 24)
            let nameLen = u16(data, offset + 28)
            let extraLen = u16(data, offset + 30)
            let commentLen = u16(data, offset + 32)
            let local = u32(data, offset + 42)
            guard offset + 46 + nameLen <= data.count else { return nil }
            let nameData = data.subdata(in: (data.startIndex + offset + 46)..<(data.startIndex + offset + 46 + nameLen))
            if let name = String(data: nameData, encoding: .utf8) {
                result[name] = Entry(method: method, compressedSize: csize, size: size, localOffset: local)
            }
            offset += 46 + nameLen + extraLen + commentLen
        }
        return result
    }

    static func read(_ entry: Entry, from data: Data) -> Data? {
        guard entry.size <= maxEntryBytes, entry.localOffset + 30 <= data.count,
              u32(data, entry.localOffset) == 0x04034b50 else { return nil }
        let start = entry.localOffset + 30 + u16(data, entry.localOffset + 26) + u16(data, entry.localOffset + 28)
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count else { return nil }
        let raw = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
        switch entry.method {
        case 0: return raw
        case 8:
            guard entry.size > 0 else { return Data() }
            var out = Data(count: entry.size)
            let written = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, entry.size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            return written == entry.size ? out : nil
        default: return nil
        }
    }
}

// MARK: - Cards from a table

nonisolated enum SpreadsheetCardLayout {
    /// Readable, centered text: larger for short entries, smaller as the text gets longer.
    static func bodySize(for text: String) -> Double {
        switch text.count {
        case ..<40: 0.05
        case ..<120: 0.04
        case ..<300: 0.032
        default: 0.026
        }
    }

    static func items(front: String, back: String, headers: [String]) -> [TextItem] {
        var items: [TextItem] = []
        for (side, text) in [(0, front), (1, back)] {
            let header = headers.indices.contains(side) ? headers[side] : ""
            if !header.isEmpty {
                items.append(TextItem(side: side, text: header, x: 0.05, y: 0.04, w: 0.9, size: 0.03, centered: true))
            }
            guard !text.isEmpty else { continue }
            let size = bodySize(for: text)
            // Roughly vertically centered: estimate the line count from the characters per line.
            let perLine = max(1.0, 0.86 / (size * 0.55))
            let lines = max(1.0, (Double(text.count) / perLine).rounded(.up))
            let height = lines * size * 1.5 * 0.6      // the card is 5:3, so height ≈ 0.6 × width
            let y = min(max(0.5 - height / 2, 0.12), 0.7)
            items.append(TextItem(side: side, text: text, x: 0.06, y: y, w: 0.88, size: size, centered: true))
        }
        return items
    }
}
