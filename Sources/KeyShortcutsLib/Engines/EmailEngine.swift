import Foundation

// Parses EML/EMLX (RFC 822) into HTML or plain text.
// MSG (Outlook compound binary) is NOT supported — it requires a heavy parser library.
final class EmailEngine: ConversionEngine {
    static let shared = EmailEngine()
    let engineName = "Built-in Email (RFC 822 parser)"

    private init() {}

    func availability(for pair: ConversionPair) -> EngineAvailability {
        if pair.source == .msg {
            return .unsupportedOnThisOS("MSG (Outlook) format is not supported in the built-in engine")
        }
        return .available
    }

    func convert(item: ConversionItem, to outputURL: URL, progress: @escaping (Double) -> Void) throws {
        let src = item.sourceURL
        progress(0.1)

        let raw: Data
        if item.detectedSourceFormat == .emlx {
            raw = try readEmlxPayload(url: src)
        } else {
            raw = try Data(contentsOf: src)
        }
        progress(0.4)

        guard let text = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) else {
            throw ConversionError.loadFailed("Cannot decode email text from \(src.lastPathComponent)")
        }

        let parsed = parseRFC822(text)
        progress(0.7)

        let output: Data
        switch item.targetFormat {
        case .html:
            let html = renderHTML(parsed)
            guard let d = html.data(using: .utf8) else {
                throw ConversionError.writeFailed("HTML encode failed")
            }
            output = d
        case .txt:
            let plain = renderPlain(parsed)
            guard let d = plain.data(using: .utf8) else {
                throw ConversionError.writeFailed("Plain text encode failed")
            }
            output = d
        default:
            throw ConversionError.unsupported("Email engine cannot write \(item.targetFormat.displayName)")
        }

        try output.write(to: outputURL, options: .atomic)
        progress(1.0)
    }

    // MARK: - EMLX payload extraction
    // EMLX files start with a decimal byte count on the first line, followed by the raw RFC 822 message.

    private func readEmlxPayload(url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let newline = text.firstIndex(of: "\n") else {
            return data
        }
        let countStr = String(text[text.startIndex..<newline]).trimmingCharacters(in: .whitespaces)
        guard let byteCount = Int(countStr) else { return data }
        let offset = text.distance(from: text.startIndex, to: text.index(after: newline))
        let startByte = data.index(data.startIndex, offsetBy: offset)
        let endByte   = data.index(startByte, offsetBy: min(byteCount, data.count - offset))
        return data[startByte..<endByte]
    }

    // MARK: - RFC 822 parser (headers + body)

    private struct ParsedEmail {
        var headers: [(key: String, value: String)] = []
        var bodyText: String = ""
        var bodyHTML: String = ""

        func header(_ key: String) -> String? {
            headers.first { $0.key.lowercased() == key.lowercased() }?.value
        }
    }

    private func parseRFC822(_ raw: String) -> ParsedEmail {
        var email = ParsedEmail()
        let lines = raw.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var i = 0

        // Parse headers
        while i < lines.count {
            let line = lines[i]
            if line.isEmpty { i += 1; break }
            if line.hasPrefix("\t") || line.hasPrefix(" ") {
                // Header continuation
                if !email.headers.isEmpty {
                    email.headers[email.headers.count - 1].value += " " + line.trimmingCharacters(in: .whitespaces)
                }
            } else if let colon = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                email.headers.append((key: key, value: val))
            }
            i += 1
        }

        // Body — everything after the blank line
        let body = lines[i...].joined(separator: "\n")

        // Simple MIME multipart detection
        if let ct = email.header("Content-Type"), ct.lowercased().contains("multipart") {
            let boundary = extractBoundary(ct)
            let parts = splitMultipart(body: body, boundary: boundary)
            for part in parts {
                let (partHeaders, partBody) = splitHeadersBody(part)
                let partCT = partHeaders.first { $0.key.lowercased() == "content-type" }?.value ?? ""
                let encoding = partHeaders.first { $0.key.lowercased() == "content-transfer-encoding" }?.value ?? ""
                let decoded = decodeBody(partBody, encoding: encoding)
                if partCT.lowercased().contains("text/html") {
                    email.bodyHTML = decoded
                } else if partCT.lowercased().contains("text/plain") {
                    email.bodyText = decoded
                }
            }
        } else {
            let encoding = email.header("Content-Transfer-Encoding") ?? ""
            let decoded = decodeBody(body, encoding: encoding)
            if let ct = email.header("Content-Type"), ct.lowercased().contains("html") {
                email.bodyHTML = decoded
            } else {
                email.bodyText = decoded
            }
        }

        return email
    }

    private func extractBoundary(_ ct: String) -> String {
        // boundary="something" or boundary=something
        let components = ct.components(separatedBy: ";")
        for part in components {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.lowercased().hasPrefix("boundary") {
                let val = p.components(separatedBy: "=").dropFirst().joined(separator: "=")
                    .trimmingCharacters(in: .init(charactersIn: " \""))
                return val
            }
        }
        return ""
    }

    private func splitMultipart(body: String, boundary: String) -> [String] {
        guard !boundary.isEmpty else { return [body] }
        let sep = "--" + boundary
        return body.components(separatedBy: sep).dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
    }

    private func splitHeadersBody(_ part: String) -> ([(key: String, value: String)], String) {
        let lines = part.components(separatedBy: "\n")
        var headers: [(key: String, value: String)] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].hasSuffix("\r") ? String(lines[i].dropLast()) : lines[i]
            if line.isEmpty { i += 1; break }
            if let colon = line.firstIndex(of: ":") {
                let k = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers.append((key: k, value: v))
            }
            i += 1
        }
        let body = lines[i...].joined(separator: "\n")
        return (headers, body)
    }

    private func decodeBody(_ body: String, encoding: String) -> String {
        let enc = encoding.lowercased().trimmingCharacters(in: .whitespaces)
        if enc == "base64" {
            let stripped = body.components(separatedBy: .newlines).joined()
            if let data = Data(base64Encoded: stripped, options: .ignoreUnknownCharacters),
               let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                return s
            }
        } else if enc == "quoted-printable" {
            return decodeQP(body)
        }
        return body
    }

    private func decodeQP(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "=" {
                let j = s.index(i, offsetBy: 1, limitedBy: s.endIndex) ?? s.endIndex
                let k = s.index(j, offsetBy: 1, limitedBy: s.endIndex) ?? s.endIndex
                let l = s.index(k, offsetBy: 1, limitedBy: s.endIndex) ?? s.endIndex
                let hex = String(s[j..<l])
                if hex == "\r\n" || hex == "\n" { i = l; continue }
                if let code = UInt8(hex, radix: 16) {
                    result.append(Character(UnicodeScalar(code)))
                    i = l
                } else {
                    result.append(s[i]); i = s.index(after: i)
                }
            } else {
                result.append(s[i]); i = s.index(after: i)
            }
        }
        return result
    }

    // MARK: - Renderers

    private func renderHTML(_ email: ParsedEmail) -> String {
        if !email.bodyHTML.isEmpty { return email.bodyHTML }
        let escaped = email.bodyText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>\n")

        let from    = email.header("From") ?? ""
        let to      = email.header("To") ?? ""
        let subject = email.header("Subject") ?? ""
        let date    = email.header("Date") ?? ""

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(escapeHTML(subject))</title></head>
        <body>
        <table style="border-collapse:collapse;margin-bottom:16px">
          <tr><td><b>From:</b></td><td>\(escapeHTML(from))</td></tr>
          <tr><td><b>To:</b></td><td>\(escapeHTML(to))</td></tr>
          <tr><td><b>Subject:</b></td><td>\(escapeHTML(subject))</td></tr>
          <tr><td><b>Date:</b></td><td>\(escapeHTML(date))</td></tr>
        </table>
        <hr>
        <div>\(escaped)</div>
        </body></html>
        """
    }

    private func renderPlain(_ email: ParsedEmail) -> String {
        if !email.bodyText.isEmpty {
            let from    = email.header("From") ?? ""
            let subject = email.header("Subject") ?? ""
            let date    = email.header("Date") ?? ""
            return "From: \(from)\nSubject: \(subject)\nDate: \(date)\n\n\(email.bodyText)"
        }
        // Strip HTML tags from HTML body as fallback
        let stripped = email.bodyHTML
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        return stripped
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
