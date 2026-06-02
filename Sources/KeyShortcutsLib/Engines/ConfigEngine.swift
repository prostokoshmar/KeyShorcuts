import Foundation
import Yams

final class ConfigEngine: ConversionEngine {
    static let shared = ConfigEngine()
    let engineName = "Built-in Config (Foundation/Yams/TOML)"

    private init() {}

    func availability(for pair: ConversionPair) -> EngineAvailability { .available }

    func convert(item: ConversionItem, to outputURL: URL, progress: @escaping (Double) -> Void) throws {
        let src = item.sourceURL
        let srcFmt  = item.detectedSourceFormat
        let dstFmt  = item.targetFormat

        // CSV ↔ TSV (no intermediate dictionary needed)
        if (srcFmt == .csv && dstFmt == .tsv) || (srcFmt == .tsv && dstFmt == .csv) {
            try convertDelimited(src: src, dst: outputURL, srcFmt: srcFmt, dstFmt: dstFmt)
            progress(1.0)
            return
        }

        progress(0.2)
        let value = try load(url: src, format: srcFmt)
        progress(0.6)
        let data  = try dump(value: value, format: dstFmt)
        try data.write(to: outputURL, options: .atomic)
        progress(1.0)
    }

    // MARK: - Load to intermediate Any

    private func load(url: URL, format: ConversionFormat) throws -> Any {
        let data = try Data(contentsOf: url)
        switch format {
        case .json:
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        case .plist:
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        case .xml:
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        case .yaml:
            guard let str = String(data: data, encoding: .utf8) else {
                throw ConversionError.loadFailed("YAML is not valid UTF-8")
            }
            guard let result = try Yams.load(yaml: str) else {
                throw ConversionError.loadFailed("YAML parsed to nil")
            }
            return result
        case .toml:
            guard let str = String(data: data, encoding: .utf8) else {
                throw ConversionError.loadFailed("TOML is not valid UTF-8")
            }
            return try MiniTOML.parse(str)
        default:
            throw ConversionError.unsupported("Config engine cannot load \(format.displayName)")
        }
    }

    // MARK: - Dump from intermediate Any

    private func dump(value: Any, format: ConversionFormat) throws -> Data {
        switch format {
        case .json:
            return try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        case .plist:
            return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        case .xml:
            return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        case .yaml:
            let str = try Yams.dump(object: value)
            guard let d = str.data(using: .utf8) else {
                throw ConversionError.writeFailed("YAML serialization produced non-UTF8 data")
            }
            return d
        case .toml:
            let tomlStr = try MiniTOML.serialize(value)
            guard let d = tomlStr.data(using: .utf8) else {
                throw ConversionError.writeFailed("TOML serialization produced non-UTF8 data")
            }
            return d
        default:
            throw ConversionError.unsupported("Config engine cannot write \(format.displayName)")
        }
    }

    // MARK: - CSV/TSV

    private func convertDelimited(src: URL, dst: URL, srcFmt: ConversionFormat, dstFmt: ConversionFormat) throws {
        let srcSep: Character = srcFmt == .csv ? "," : "\t"
        let dstSep: Character = dstFmt == .csv ? "," : "\t"
        let text = try String(contentsOf: src, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        for line in lines {
            let fields = parseLine(line, separator: srcSep)
            output.append(fields.map { quoteIfNeeded($0, sep: dstSep) }.joined(separator: String(dstSep)))
        }
        let result = output.joined(separator: "\n")
        guard let data = result.data(using: .utf8) else {
            throw ConversionError.writeFailed("CSV/TSV encode failed")
        }
        try data.write(to: dst, options: .atomic)
    }

    private func parseLine(_ line: String, separator: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle() }
            else if ch == separator && !inQuotes { fields.append(current); current = "" }
            else { current.append(ch) }
        }
        fields.append(current)
        return fields
    }

    private func quoteIfNeeded(_ s: String, sep: Character) -> String {
        let needsQuote = s.contains(sep) || s.contains("\"") || s.contains("\n")
        if needsQuote { return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return s
    }
}

// MARK: - Minimal TOML parser (flat key=value, no inline tables / arrays of tables)

enum MiniTOML {
    static func parse(_ text: String) throws -> [String: Any] {
        var result: [String: Any] = [:]
        var currentSection = ""
        for rawLine in text.components(separatedBy: "\n") {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key   = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let rawVal = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            let val   = parseValue(rawVal)
            let fullKey = currentSection.isEmpty ? key : "\(currentSection).\(key)"
            result[fullKey] = val
        }
        return result
    }

    static func serialize(_ value: Any) throws -> String {
        guard let dict = value as? [String: Any] else {
            throw ConversionError.unsupported("TOML top-level must be a dictionary")
        }
        var lines: [String] = []
        for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
            lines.append("\(k) = \(toTOML(v))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func parseValue(_ s: String) -> Any {
        if s == "true"  { return true }
        if s == "false" { return false }
        if let i = Int(s)    { return i }
        if let f = Double(s) { return f }
        // Quoted string
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) ||
           (s.hasPrefix("'")  && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        // Array [a, b, c]
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = String(s.dropFirst().dropLast())
            return inner.components(separatedBy: ",").map { parseValue($0.trimmingCharacters(in: .whitespaces)) }
        }
        return s
    }

    private static func stripComment(_ line: String) -> String {
        // Naive strip — doesn't handle # inside strings
        if let idx = line.firstIndex(of: "#") { return String(line[..<idx]) }
        return line
    }

    private static func toTOML(_ v: Any) -> String {
        if let s = v as? String  { return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        if let i = v as? Int     { return "\(i)" }
        if let f = v as? Double  { return "\(f)" }
        if let b = v as? Bool    { return b ? "true" : "false" }
        if let arr = v as? [Any] { return "[\(arr.map { toTOML($0) }.joined(separator: ", "))]" }
        return "\"\(v)\""
    }
}
