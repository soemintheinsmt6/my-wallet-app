import Foundation

public enum CSVError: LocalizedError, Equatable {
    case unterminatedQuote(line: Int)
    case empty

    public var errorDescription: String? {
        switch self {
        case .unterminatedQuote(let line): "A quoted value starting on line \(line) is never closed."
        case .empty: "The file has no rows."
        }
    }
}

/// RFC 4180 CSV reading and writing.
///
/// Written by hand rather than pulled in as a dependency because the rules that matter here are
/// narrow and worth testing directly: values holding commas, quotes or newlines must survive a
/// round trip, and a file exported from this app must re-import unchanged.
public enum CSV {
    public static func encode(rows: [[String]]) -> String {
        rows.map { row in row.map(field).joined(separator: ",") }.joined(separator: "\r\n")
    }

    /// Quotes only when required, doubling any embedded quote.
    private static func field(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"")
            || value.contains("\n") || value.contains("\r")
            // Leading/trailing spaces would otherwise be ambiguous to other readers.
            || value.hasPrefix(" ") || value.hasSuffix(" ")
        guard needsQuoting else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Parses into rows of fields. Handles quoted fields containing commas and newlines, CRLF and
    /// LF endings, and a trailing newline. Blank lines are skipped.
    public static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var quoteStartLine = 1
        var line = 1
        // A leading byte-order mark would otherwise become part of the first header.
        var characters = Substring(text)
        if characters.hasPrefix("\u{FEFF}") { characters = characters.dropFirst() }
        var iterator = characters.makeIterator()

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            endField()
            // A blank line is a single empty field; drop it rather than importing an empty record.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        // Swift treats CRLF as a single grapheme cluster, so it is matched alongside lone CR and LF
        // rather than by looking ahead a character.
        let newlines: Set<Character> = ["\r\n", "\r", "\n"]
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    // A doubled quote is an escaped quote; anything else closes the field.
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    if newlines.contains(character) { line += 1 }
                    field.append(character)
                }
                continue
            }
            if newlines.contains(character) {
                line += 1
                endRow()
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
                quoteStartLine = line
            case ",":
                endField()
            default:
                field.append(character)
            }
        }

        if inQuotes { throw CSVError.unterminatedQuote(line: quoteStartLine) }
        // Whatever is buffered at EOF is a final row unless the file ended on a newline.
        if !field.isEmpty || !row.isEmpty { endRow() }
        guard !rows.isEmpty else { throw CSVError.empty }
        return rows
    }
}
