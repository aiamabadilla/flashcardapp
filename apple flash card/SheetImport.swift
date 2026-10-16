import Foundation
import SwiftData
import Compression
import UniformTypeIdentifiers

/// Turns a spreadsheet into flashcards. Column A becomes the front of each card and column B the
/// back; every row is one card. Only the text is imported, so it can be annotated in the app.
///
/// Supports Excel `.xlsx` (first sheet) and `.csv` / `.tsv` / plain text. Everything is read on
/// the device; nothing leaves it.
enum SheetImport {
    /// Limits that keep a huge or hostile file from exhausting memory.
    nonisolated static let maxRows = 5_000
    nonisolated static let maxCellLength = 4_000
    nonisolated static let maxFileBytes = 25 * 1_024 * 1_024
    nonisolated static let maxXMLBytes = 60 * 1_024 * 1_024

    nonisolated struct Row: Equatable {
        var front: String
        var back: String
    }

    nonisolated enum SheetError: LocalizedError {
        case unreadable, unsupported, empty, tooManyRows, tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn't read that file."
            case .unsupported: "That file type isn't supported. Save it as .xlsx or .csv and try again."
            case .empty: "No text was found. Put the front of each card in column A and the back in column B."
            case .tooManyRows: "That file has more than \(SheetImport.maxRows) rows. Split it into smaller files."
            case .tooLarge: "That file is too large to import."
            }
        }
    }

    /// File types the picker offers.
    static var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText]
        if let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") { types.append(xlsx) }
        if let byExtension = UTType(filenameExtension: "xlsx"), !types.contains(byExtension) {
            types.append(byExtension)
        }
        return types
    }

    // MARK: Reading a file

    /// Reads the rows of a picked file. Handles the security scope of files from the Files app.
    @MainActor static func readRows(at url: URL) throws -> [Row] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxFileBytes else { throw SheetError.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw SheetError.unreadable }
        return try parse(data, fileExtension: url.pathExtension)
    }

    /// Rows (front, back) from the bytes of an .xlsx, .csv or .tsv file.
    nonisolated static func parse(_ data: Data, fileExtension: String = "") throws -> [Row] {
        guard data.count <= maxFileBytes else { throw SheetError.tooLarge }
        let table: [[String]]
        if data.starts(with: [0x50, 0x4B]) {                 // "PK": a zip, so .xlsx
            table = try xlsxTable(from: data)
        } else if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) {   // old binary .xls
            throw SheetError.unsupported
        } else {
            table = try delimitedTable(from: data, fileExtension: fileExtension)
        }

        var rows: [Row] = []
        for cells in table {
            let front = clean(cells.count > 0 ? cells[0] : "")
            let back = clean(cells.count > 1 ? cells[1] : "")
            if front.isEmpty && back.isEmpty { continue }
            rows.append(Row(front: front, back: back))
            if rows.count > maxRows { throw SheetError.tooManyRows }
        }
        guard !rows.isEmpty else { throw SheetError.empty }
        return rows
    }

    nonisolated private static func clean(_ text: String) -> String {
        var s = text
        // Excel escapes some control characters inside text as _xHHHH_.
        if s.contains("_x000") {
            s = s.replacingOccurrences(of: "_x000D_", with: "")
                 .replacingOccurrences(of: "_x000A_", with: "\n")
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > maxCellLength { s = String(s.prefix(maxCellLength)) }
        return s
    }

    // MARK: Creating cards

    /// Adds one card per row at the top of the deck, in file order (new cards go first in IMSTUDY).
    /// Cards get the usual new-card paper: blank front, lined back.
    @MainActor @discardableResult
    static func addCards(_ rows: [Row], to deck: Deck, in context: ModelContext) -> [Card] {
        guard !rows.isEmpty else { return [] }
        for other in deck.liveCards { other.order += rows.count }
        var added: [Card] = []
        for (index, row) in rows.enumerated() {
            let card = Card(order: index)
            card.applyNewCardPaper()
            card.textItemsJSON = textItemsJSON(for: row)
            deck.cards.append(card)
            added.append(card)
        }
        context.saveReporting("imported cards")
        return added
    }

    /// Lets the person take back an import into an existing deck for a few seconds.
    @MainActor static func offerUndo(_ added: [Card], in deck: Deck, context: ModelContext) {
        guard !added.isEmpty else { return }
        UndoCenter.shared.offer("Imported \(plural(added.count, "card"))") {
            for card in added {
                deck.cards.removeAll { $0 === card }
                context.delete(card)
            }
            deck.renumber()
            context.saveReporting()
        }
    }

    /// The typed text boxes for one row: column A on the front, column B on the back.
    @MainActor static func textItemsJSON(for row: Row) -> String {
        var items: [TextItem] = []
        if !row.front.isEmpty {
            items.append(TextItem(side: 0, text: row.front, x: 0.02, y: 0.03, w: 0.96, size: fontSize(for: row.front)))
        }
        if !row.back.isEmpty {
            items.append(TextItem(side: 1, text: row.back, x: 0.02, y: 0.03, w: 0.96, size: fontSize(for: row.back)))
        }
        guard let data = try? JSONEncoder().encode(items), let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    /// Long text gets a smaller font so it still fits on the card.
    nonisolated static func fontSize(for text: String) -> Double {
        switch text.count {
        case ..<200: 0.03
        case ..<450: 0.024
        case ..<900: 0.018
        default: 0.014
        }
    }

    // MARK: CSV / TSV

    nonisolated static func delimitedTable(from data: Data, fileExtension: String) throws -> [[String]] {
        guard let text = decode(data) else { throw SheetError.unsupported }
        let separator = delimiter(for: text, fileExtension: fileExtension)
        return parseDelimited(text, delimiter: separator)
    }

    nonisolated private static func decode(_ data: Data) -> String? {
        // A run of zero bytes means a binary file, not text.
        if data.prefix(2048).contains(0) {
            // UTF-16 text has zero bytes too, but starts with a byte order mark.
            if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
                return String(data: data, encoding: .utf16)
            }
            return nil
        }
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }
        if let s = String(data: body, encoding: .utf8) { return s }
        return String(data: body, encoding: .windowsCP1252) ?? String(data: body, encoding: .isoLatin1)
    }

    /// Tab for .tsv; otherwise whichever of comma, semicolon or tab the first line uses most
    /// (Excel in some countries saves CSV with semicolons).
    nonisolated private static func delimiter(for text: String, fileExtension: String) -> Unicode.Scalar {
        if fileExtension.lowercased() == "tsv" { return "\t" }
        var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for scalar in text.unicodeScalars {
            if scalar == "\"" { inQuotes.toggle(); continue }
            if inQuotes { continue }
            if scalar == "\n" || scalar == "\r" { break }
            if counts[scalar] != nil { counts[scalar]! += 1 }
        }
        let best = counts.max { $0.value < $1.value }
        if let best, best.value > 0 { return best.key }
        return ","
    }

    /// A small CSV reader: quoted fields, doubled quotes, and line breaks inside quotes.
    nonisolated static func parseDelimited(_ text: String, delimiter: Unicode.Scalar) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        let scalars = Array(text.unicodeScalars)
        var i = 0

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                endField()
            } else if c == "\n" {
                endRow()
            } else if c == "\r" {
                endRow()
                if i + 1 < scalars.count && scalars[i + 1] == "\n" { i += 1 }
            } else {
                field.append(c)
            }
            i += 1
            if rows.count > maxRows + 1 { break }   // far past the limit; the caller reports it
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    // MARK: Excel (.xlsx)

    /// Column A and B text of every row in the workbook's first sheet.
    nonisolated static func xlsxTable(from data: Data) throws -> [[String]] {
        let zip = try MiniZip(data: data)

        var sharedStrings: [String] = []
        if let shared = try zip.read("xl/sharedStrings.xml", maxBytes: maxXMLBytes) {
            let parser = SharedStringsParser()
            run(parser, on: shared)
            sharedStrings = parser.strings
        }

        let sheetPath = try firstSheetPath(in: zip)
        guard let sheetData = try zip.read(sheetPath, maxBytes: maxXMLBytes) else { throw SheetError.unreadable }
        let sheet = SheetXMLParser(sharedStrings: sharedStrings)
        run(sheet, on: sheetData)

        return sheet.rows.map { cells in [cells[0] ?? "", cells[1] ?? ""] }
    }

    nonisolated private static func run(_ delegate: XMLParserDelegate, on data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
    }

    /// Path of the first sheet in tab order, falling back to the usual `sheet1.xml`.
    nonisolated private static func firstSheetPath(in zip: MiniZip) throws -> String {
        let fallback = "xl/worksheets/sheet1.xml"
        guard let workbook = try zip.read("xl/workbook.xml", maxBytes: maxXMLBytes),
              let rels = try zip.read("xl/_rels/workbook.xml.rels", maxBytes: maxXMLBytes) else {
            return zip.has(fallback) ? fallback : (zip.firstName(prefix: "xl/worksheets/sheet") ?? fallback)
        }
        let book = WorkbookParser()
        run(book, on: workbook)
        let relations = RelationshipsParser()
        run(relations, on: rels)

        if let id = book.firstSheetRelationshipID, let target = relations.targets[id] {
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            if zip.has(path) { return path }
        }
        return zip.has(fallback) ? fallback : (zip.firstName(prefix: "xl/worksheets/sheet") ?? fallback)
    }
}

// MARK: - XML parsers

/// An element name without its namespace prefix ("x:row" gives "row"), since some programs write
/// spreadsheets with prefixed tags.
nonisolated private func localName(_ name: String) -> String {
    guard let colon = name.lastIndex(of: ":") else { return name }
    return String(name[name.index(after: colon)...])
}

/// The first `<sheet>` in workbook.xml (the leftmost tab) and its relationship id.
nonisolated private final class WorkbookParser: NSObject, XMLParserDelegate {
    var firstSheetRelationshipID: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard firstSheetRelationshipID == nil, localName(elementName) == "sheet" else { return }
        firstSheetRelationshipID = attributeDict["r:id"]
            ?? attributeDict.first { $0.key.hasSuffix(":id") }?.value
    }
}

/// workbook.xml.rels: relationship id to file path.
nonisolated private final class RelationshipsParser: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard localName(elementName) == "Relationship", let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        targets[id] = target
    }
}

/// sharedStrings.xml: the text cells point into this list by position.
nonisolated private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inItem = false
    private var inText = false
    private var phoneticDepth = 0   // furigana runs are not part of the text

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "si": inItem = true; current = ""
        case "rPh": phoneticDepth += 1
        case "t": if inItem && phoneticDepth == 0 { inText = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch localName(elementName) {
        case "t": inText = false
        case "rPh": phoneticDepth = max(0, phoneticDepth - 1)
        case "si":
            strings.append(current)
            inItem = false
            if strings.count > 500_000 { parser.abortParsing() }
        default: break
        }
    }
}

/// A worksheet: each row's text cells by column number (0 = A, 1 = B).
nonisolated private final class SheetXMLParser: NSObject, XMLParserDelegate {
    var rows: [[Int: String]] = []
    private let sharedStrings: [String]
    private var current: [Int: String] = [:]
    private var column = 0
    private var cellType = ""
    private var text = ""
    private var capturing = false
    private var inInline = false
    private var phoneticDepth = 0

    init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "row":
            current = [:]
        case "c":
            cellType = attributeDict["t"] ?? ""
            column = attributeDict["r"].flatMap(Self.columnIndex) ?? ((current.keys.max() ?? -1) + 1)
            text = ""
        case "v":
            capturing = true
        case "is":
            inInline = true
        case "rPh":
            phoneticDepth += 1
        case "t":
            if inInline && phoneticDepth == 0 { capturing = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch localName(elementName) {
        case "v", "t":
            capturing = false
        case "rPh":
            phoneticDepth = max(0, phoneticDepth - 1)
        case "is":
            inInline = false
        case "c":
            var value = ""
            switch cellType {
            case "s":
                if let index = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   sharedStrings.indices.contains(index) { value = sharedStrings[index] }
            case "b":
                value = text.trimmingCharacters(in: .whitespaces) == "1" ? "TRUE" : "FALSE"
            case "e":
                value = ""
            default:
                value = text
            }
            // Only columns A and B are used.
            if column <= 1, !value.isEmpty { current[column] = value }
        case "row":
            rows.append(current)
            if rows.count > SheetImport.maxRows * 4 { parser.abortParsing() }
        default:
            break
        }
    }

    /// "A1" gives 0, "B7" gives 1, "AA3" gives 26.
    private static func columnIndex(_ reference: String) -> Int? {
        var n = 0
        var sawLetter = false
        for scalar in reference.unicodeScalars {
            guard scalar.value >= 65 && scalar.value <= 90 else { break }
            n = n * 26 + Int(scalar.value - 64)
            sawLetter = true
        }
        return sawLetter ? n - 1 : nil
    }
}

// MARK: - Zip reading

/// Reads files out of a zip archive (an .xlsx is a zip). Handles stored and deflated entries,
/// which is all spreadsheet programs write.
nonisolated struct MiniZip {
    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localOffset: Int
    }

    private let bytes: [UInt8]
    private var entries: [String: Entry] = [:]

    init(data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw SheetImport.SheetError.unreadable }

        // The end-of-central-directory record is near the end of the file.
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while i >= lowest {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw SheetImport.SheetError.unreadable }

        let count = Int(try u16(eocd + 10))
        var p = Int(try u32(eocd + 16))
        for _ in 0..<count {
            let signature = try u32(p)
            guard signature == 0x0201_4B50 else { throw SheetImport.SheetError.unreadable }
            let method = try u16(p + 10)
            let compressed = try u32(p + 20)
            let uncompressed = try u32(p + 24)
            let nameLength = Int(try u16(p + 28))
            let extraLength = Int(try u16(p + 30))
            let commentLength = Int(try u16(p + 32))
            let offset = try u32(p + 42)
            guard p + 46 + nameLength <= bytes.count else { throw SheetImport.SheetError.unreadable }
            let nameBytes = bytes[(p + 46)..<(p + 46 + nameLength)]
            let name = String(decoding: nameBytes, as: UTF8.self)
            // 0xFFFFFFFF marks zip64, which spreadsheets don't need.
            if compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF, offset != 0xFFFF_FFFF {
                entries[name] = Entry(method: method, compressedSize: Int(compressed),
                                      uncompressedSize: Int(uncompressed), localOffset: Int(offset))
            }
            p += 46 + nameLength + extraLength + commentLength
        }
    }

    func has(_ name: String) -> Bool { entries[name] != nil }

    /// The alphabetically first entry whose name starts with the prefix and ends in .xml.
    func firstName(prefix: String) -> String? {
        entries.keys.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".xml") }.sorted().first
    }

    /// The file's bytes, or nil if the archive has no such file.
    func read(_ name: String, maxBytes: Int) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        guard entry.uncompressedSize <= maxBytes else { throw SheetImport.SheetError.tooLarge }

        let o = entry.localOffset
        let signature = try u32(o)
        guard signature == 0x0403_4B50 else { throw SheetImport.SheetError.unreadable }
        let nameLength = Int(try u16(o + 26))
        let extraLength = Int(try u16(o + 28))
        let start = o + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count, start <= end else { throw SheetImport.SheetError.unreadable }
        let packed = bytes[start..<end]

        switch entry.method {
        case 0:
            return Data(packed)
        case 8:
            guard entry.uncompressedSize > 0 else { return Data() }
            guard !packed.isEmpty else { throw SheetImport.SheetError.unreadable }
            var output = [UInt8](repeating: 0, count: entry.uncompressedSize)
            let written = packed.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { target in
                    compression_decode_buffer(target.baseAddress!, target.count,
                                              source.baseAddress!, source.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.uncompressedSize else { throw SheetImport.SheetError.unreadable }
            return Data(output)
        default:
            throw SheetImport.SheetError.unsupported
        }
    }

    private func u16(_ at: Int) throws -> UInt16 {
        guard at >= 0, at + 2 <= bytes.count else { throw SheetImport.SheetError.unreadable }
        return UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private func u32(_ at: Int) throws -> UInt32 {
        guard at >= 0, at + 4 <= bytes.count else { throw SheetImport.SheetError.unreadable }
        return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
