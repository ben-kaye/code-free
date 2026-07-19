import Foundation

// MARK: - Segment model (parse before render)

/// Block-level chat content after lifting code fences and display math.
enum ChatBlock: Hashable, Sendable {
    case prose([ChatInline])
    case code(language: String?, body: String)
    /// Complete display-math region (delimiters already stripped).
    case displayMath(String)
}

/// Inline pieces inside a prose block.
enum ChatInline: Hashable, Sendable {
    case markdown(String)
    /// Complete inline math (delimiters stripped).
    case math(String)
}

/// Inline with streaming-stable identity (content fingerprint + occurrence).
struct IdentifiedChatInline: Identifiable, Hashable, Sendable {
    let id: String
    let inline: ChatInline
}

/// Block-level content with stable ids for ForEach (math/code survive streaming edits).
enum IdentifiedChatContent: Hashable, Sendable {
    case prose([IdentifiedChatInline])
    case code(language: String?, body: String)
    case displayMath(String)
}

struct IdentifiedChatBlock: Identifiable, Hashable, Sendable {
    let id: String
    let content: IdentifiedChatContent
}

// MARK: - Parse cache (same source often re-rendered when parent state changes)

enum ChatParseCache {
    private static let lock = NSLock()
    private static var map: [String: [ChatBlock]] = [:]
    private static var order: [String] = []
    private static let maxEntries = 64

    static func blocks(for source: String, compute: (String) -> [ChatBlock]) -> [ChatBlock] {
        lock.lock()
        if let hit = map[source] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let value = compute(source)

        lock.lock()
        if map[source] == nil {
            map[source] = value
            order.append(source)
            while order.count > maxEntries {
                let old = order.removeFirst()
                map.removeValue(forKey: old)
            }
        }
        let result = map[source] ?? value
        lock.unlock()
        return result
    }

    /// Tests only.
    static func removeAll() {
        lock.lock()
        map.removeAll()
        order.removeAll()
        lock.unlock()
    }
}

// MARK: - Balance (streaming-safe render gate)

/// Tracks whether a LaTeX math body is structurally complete enough to typeset.
/// Incomplete regions must not be handed to a math backend (avoids flash of broken equations).
enum MathBalance {
    /// `true` when braces / environments look closed and the source is non-empty.
    static func mayRender(_ latex: String) -> Bool {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var braceDepth = 0
        var envDepth = 0
        let chars = Array(trimmed)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                // Escaped brace
                if i + 1 < chars.count, chars[i + 1] == "{" || chars[i + 1] == "}" {
                    i += 2
                    continue
                }
                // \begin{...} / \end{...}
                if match(chars, at: i, "\\begin") {
                    if let (next, _) = readEnvName(chars, from: i + 6) {
                        envDepth += 1
                        i = next
                        continue
                    }
                }
                if match(chars, at: i, "\\end") {
                    if let (next, _) = readEnvName(chars, from: i + 4) {
                        envDepth = max(0, envDepth - 1)
                        i = next
                        continue
                    }
                }
                // Lone trailing backslash → incomplete control sequence
                if i + 1 >= chars.count { return false }
                i += 1
                continue
            }
            if c == "{" {
                braceDepth += 1
            } else if c == "}" {
                braceDepth = max(0, braceDepth - 1)
            }
            i += 1
        }

        return braceDepth == 0 && envDepth == 0
    }

    private static func readEnvName(
        _ chars: [Character],
        from start: Int
    ) -> (Int, String)? {
        var i = start
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        guard i < chars.count, chars[i] == "{" else { return nil }
        i += 1
        let nameStart = i
        while i < chars.count, chars[i] != "}" {
            i += 1
        }
        guard i < chars.count, chars[i] == "}" else { return nil }
        let name = String(chars[nameStart..<i])
        return (i + 1, name)
    }

    private static func match(_ chars: [Character], at i: Int, _ s: String) -> Bool {
        let needle = Array(s)
        guard i + needle.count <= chars.count else { return false }
        for (offset, c) in needle.enumerated() where chars[i + offset] != c {
            return false
        }
        return true
    }
}

// MARK: - Parser

/// Full-message parser: code fences → display math → inline math → markdown spans.
/// Incomplete delimiters stay literal text (streaming-safe).
///
/// Does **not** live on the wire. Protocol events remain opaque text; the shell parses for display only.
enum ChatContentParser {
    /// Parse + assign streaming-stable segment ids (preferred for views).
    static func parseIdentified(_ source: String) -> [IdentifiedChatBlock] {
        identify(parse(source))
    }

    static func parse(_ source: String) -> [ChatBlock] {
        ChatParseCache.blocks(for: source, compute: parseUncached)
    }

    /// Test/helpers: bypass LRU cache.
    static func parseUncached(_ source: String) -> [ChatBlock] {
        guard !source.isEmpty else { return [] }

        var blocks: [ChatBlock] = []
        var proseBuffer = ""
        let chars = Array(source)
        var i = 0

        func flushProse() {
            guard !proseBuffer.isEmpty else { return }
            // Block structure is a view tree (paragraph / list row), not presentationIntent.
            // Each unit is markdown-inlines only so Text never smashes adjacent blocks.
            for unit in splitProseUnits(proseBuffer) {
                let inlines = splitInlines(unit)
                if !inlines.isEmpty {
                    blocks.append(.prose(inlines))
                }
            }
            proseBuffer = ""
        }

        while i < chars.count {
            // 1) Fenced code first
            if isFenceOpen(chars, at: i) {
                flushProse()
                let (block, next) = consumeCodeFence(chars, from: i)
                blocks.append(block)
                i = next
                continue
            }

            // 2) Display math $$...$$
            if match(chars, at: i, "$$") {
                if let close = findClosing(chars, from: i + 2, delimiter: "$$") {
                    flushProse()
                    let latex = String(chars[(i + 2)..<close])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    blocks.append(.displayMath(latex))
                    i = close + 2
                    continue
                }
            }

            // 2b) Display math \[...\]
            if match(chars, at: i, "\\[") {
                if let close = findClosing(chars, from: i + 2, delimiter: "\\]") {
                    flushProse()
                    let latex = String(chars[(i + 2)..<close])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    blocks.append(.displayMath(latex))
                    i = close + 2
                    continue
                }
            }

            proseBuffer.append(chars[i])
            i += 1
        }

        flushProse()
        return blocks
    }

    // MARK: Stable ids

    /// Content fingerprint + occurrence so duplicate equations get distinct ids,
    /// while an unchanged equation keeps the same id as the message streams.
    static func identify(_ blocks: [ChatBlock]) -> [IdentifiedChatBlock] {
        var seen: [String: Int] = [:]
        return blocks.map { block in
            switch block {
            case .prose(let inlines):
                let identifiedInlines = identifyInlines(inlines, seen: &seen)
                let key = "p:" + identifiedInlines.map(\.id).joined(separator: "|")
                return IdentifiedChatBlock(
                    id: nextId(key, seen: &seen),
                    content: .prose(identifiedInlines)
                )
            case .code(let language, let body):
                let key = "c:\(language ?? ""):\(body)"
                return IdentifiedChatBlock(
                    id: nextId(key, seen: &seen),
                    content: .code(language: language, body: body)
                )
            case .displayMath(let latex):
                let key = "d:\(latex)"
                return IdentifiedChatBlock(
                    id: nextId(key, seen: &seen),
                    content: .displayMath(latex)
                )
            }
        }
    }

    static func identifyInlines(
        _ inlines: [ChatInline],
        seen: inout [String: Int]
    ) -> [IdentifiedChatInline] {
        // Math keys use a dedicated counter space so prose growth does not remount equations.
        inlines.map { inline in
            let key: String
            switch inline {
            case .markdown(let s): key = "m:\(s)"
            case .math(let latex): key = "i:\(latex)"
            }
            return IdentifiedChatInline(id: nextId(key, seen: &seen), inline: inline)
        }
    }

    private static func nextId(_ key: String, seen: inout [String: Int]) -> String {
        let n = seen[key, default: 0]
        seen[key] = n + 1
        // Keep ids short but stable; full key would bloat ForEach identity for long prose.
        let digest = stableDigest(key)
        return "\(digest)#\(n)"
    }

    /// FNV-1a 64-bit hex — stable across process launches (unlike Hasher).
    private static func stableDigest(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    // MARK: Block units (within prose)

    /// Split a prose region into paragraph / list-row units.
    /// Blank lines separate paragraphs; tight list lines become one unit each.
    /// Soft single newlines inside a non-list paragraph collapse to spaces (reflow).
    static func splitProseUnits(_ source: String) -> [String] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.isEmpty else { return [] }

        var units: [String] = []
        // Split on blank lines (one or more); keep chunk interior intact for list detection.
        let chunks = normalized.components(separatedBy: "\n\n")
        for chunk in chunks {
            let trimmedEnds = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedEnds.isEmpty { continue }

            if isListChunk(chunk) {
                for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
                    let lineStr = String(line).trimmingCharacters(in: .whitespaces)
                    if !lineStr.isEmpty {
                        units.append(lineStr)
                    }
                }
            } else {
                // Soft breaks → space so a single Text reflows to the column.
                let collapsed = trimmedEnds
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !collapsed.isEmpty {
                    units.append(collapsed)
                }
            }
        }
        return units
    }

    /// True when every non-empty line looks like an ordered or unordered list marker.
    private static func isListChunk(_ chunk: String) -> Bool {
        let lines = chunk
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy(isListLine)
    }

    private static func isListLine(_ line: String) -> Bool {
        // 1. / 1) / - / * / +
        if line.range(of: #"^\d+[.)]\s+\S"#, options: .regularExpression) != nil {
            return true
        }
        if line.range(of: #"^[-*+]\s+\S"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    // MARK: Inline (within prose)

    private static func splitInlines(_ source: String) -> [ChatInline] {
        var result: [ChatInline] = []
        var mdBuffer = ""
        let chars = Array(source)
        var i = 0

        func flushMarkdown() {
            guard !mdBuffer.isEmpty else { return }
            result.append(.markdown(mdBuffer))
            mdBuffer = ""
        }

        while i < chars.count {
            // Protect `$` inside `code` spans
            if chars[i] == "`" {
                let (span, next) = consumeBacktickSpan(chars, from: i)
                mdBuffer.append(span)
                i = next
                continue
            }

            // Inline \( ... \)
            if match(chars, at: i, "\\(") {
                if let close = findClosing(chars, from: i + 2, delimiter: "\\)") {
                    flushMarkdown()
                    result.append(.math(String(chars[(i + 2)..<close])))
                    i = close + 2
                    continue
                }
            }

            // Inline $...$ (not $$; no leading/trailing space; no newlines)
            if chars[i] == "$", !match(chars, at: i, "$$") {
                if let (latex, next) = consumeInlineDollarMath(chars, from: i) {
                    flushMarkdown()
                    result.append(.math(latex))
                    i = next
                    continue
                }
            }

            mdBuffer.append(chars[i])
            i += 1
        }

        flushMarkdown()
        return result
    }

    private static func consumeInlineDollarMath(
        _ chars: [Character],
        from start: Int
    ) -> (String, Int)? {
        guard start < chars.count, chars[start] == "$" else { return nil }
        let contentStart = start + 1
        guard contentStart < chars.count else { return nil }
        if chars[contentStart].isWhitespace { return nil }

        var j = contentStart
        while j < chars.count {
            if chars[j] == "\\", j + 1 < chars.count {
                j += 2
                continue
            }
            if chars[j] == "\n" { return nil }
            if chars[j] == "$" {
                if j == contentStart { return nil }
                if chars[j - 1].isWhitespace { return nil }
                return (String(chars[contentStart..<j]), j + 1)
            }
            j += 1
        }
        return nil
    }

    // MARK: Code fence

    private static func isFenceOpen(_ chars: [Character], at i: Int) -> Bool {
        guard match(chars, at: i, "```") else { return false }
        if i == 0 { return true }
        return chars[i - 1] == "\n"
    }

    /// Unclosed fence → remainder is code (stream-friendly).
    private static func consumeCodeFence(
        _ chars: [Character],
        from start: Int
    ) -> (ChatBlock, Int) {
        var i = start + 3
        var langChars: [Character] = []
        while i < chars.count, chars[i] != "\n" {
            langChars.append(chars[i])
            i += 1
        }
        if i < chars.count, chars[i] == "\n" { i += 1 }
        let language = String(langChars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyStart = i

        while i < chars.count {
            if match(chars, at: i, "```"), i == bodyStart || chars[i - 1] == "\n" {
                var body = String(chars[bodyStart..<i])
                if body.hasSuffix("\n") { body.removeLast() }
                let lang = language.isEmpty ? nil : language
                var next = i + 3
                // Drop the newline after the closing fence so following prose is clean.
                if next < chars.count, chars[next] == "\n" { next += 1 }
                return (.code(language: lang, body: body), next)
            }
            i += 1
        }

        let body = String(chars[bodyStart...])
        let lang = language.isEmpty ? nil : language
        return (.code(language: lang, body: body), chars.count)
    }

    private static func consumeBacktickSpan(
        _ chars: [Character],
        from start: Int
    ) -> (String, Int) {
        var n = 0
        var i = start
        while i < chars.count, chars[i] == "`" {
            n += 1
            i += 1
        }
        guard n > 0 else { return (String(chars[start]), start + 1) }
        let open = String(repeating: "`", count: n)
        var j = i
        while j < chars.count {
            if match(chars, at: j, open) {
                let after = j + n
                if after >= chars.count || chars[after] != "`" {
                    return (String(chars[start..<after]), after)
                }
            }
            j += 1
        }
        return (String(chars[start...]), chars.count)
    }

    private static func match(_ chars: [Character], at i: Int, _ s: String) -> Bool {
        let needle = Array(s)
        guard i + needle.count <= chars.count else { return false }
        for (offset, c) in needle.enumerated() where chars[i + offset] != c {
            return false
        }
        return true
    }

    private static func findClosing(
        _ chars: [Character],
        from start: Int,
        delimiter: String
    ) -> Int? {
        var i = start
        while i < chars.count {
            // Match delimiter first so `\)` / `\]` are closers, not escape skips.
            if match(chars, at: i, delimiter) {
                return i
            }
            if chars[i] == "\\", i + 1 < chars.count {
                i += 2
                continue
            }
            i += 1
        }
        return nil
    }
}
