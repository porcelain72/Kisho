//
//  KishoMarkdown.swift
//  Kisho
//
//  Markdown export of the block tree and import of a Markdown file into
//  blocks by heading. Both are pure functions on the model so they can be
//  tested without a window.
//
//  Export: `#`…`######` by depth, paragraphs separated by blank lines,
//  bold/italic from font traits, tags as an HTML comment (invisible when
//  rendered, recovered on import). Import: ATX and setext headings build the
//  tree; `**`, `__`, `*`, `_` and backslash escapes are understood inline;
//  everything else is kept as literal text.
//

import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import RichTextEditor

enum Markdown {

    // MARK: - Export

    static func string(from sections: [KishoSection], typography: TypographySettings? = nil) -> String {
        var out: [String] = []
        if let typography {
            // Markdown has no fonts; carry the document font the same way as
            // tags so a Kisho→Kisho round trip keeps it. Invisible when rendered.
            out.append("<!-- kisho: font \(typography.fontFamily) \(formatted(typography.fontSize)) -->")
        }
        func walk(_ list: [KishoSection], depth: Int) {
            for section in list {
                out.append(String(repeating: "#", count: min(depth, 6)) + " " + escapeInline(section.displayTitle))
                if !section.tags.isEmpty {
                    out.append("<!-- tags: " + section.tags.joined(separator: ", ") + " -->")
                }
                // Planning metadata, invisible when rendered, read back on import.
                if let status = section.status { out.append("<!-- kisho: status \(status.rawValue) -->") }
                if let colour = section.colorIndex { out.append("<!-- kisho: colour \(colour) -->") }
                if !section.synopsis.isEmpty {
                    out.append("<!-- synopsis: " + commentSafe(section.synopsis.replacingOccurrences(of: "\n", with: " ")) + " -->")
                }
                if !section.notes.isEmpty {
                    out.append("<!-- notes:\n" + commentSafe(section.notes) + "\n-->")
                }
                let body = paragraphs(section.content.attributedString)
                out.append(contentsOf: body)
                walk(section.children, depth: depth + 1)
            }
        }
        walk(sections, depth: 1)
        return out.joined(separator: "\n\n") + "\n"
    }

    /// Body text as Markdown paragraphs (one per line of the text view; empty
    /// lines dropped), with emphasis from font traits.
    private static func paragraphs(_ text: NSAttributedString) -> [String] {
        var result: [String] = []
        let full = text.string as NSString
        var location = 0
        while location < full.length {
            let lineRange = full.lineRange(for: NSRange(location: location, length: 0))
            var content = lineRange
            // Drop the line terminator from the content range.
            while content.length > 0,
                  let scalar = Unicode.Scalar(full.character(at: NSMaxRange(content) - 1)),
                  CharacterSet.newlines.contains(scalar) {
                content.length -= 1
            }
            if content.length > 0 {
                let line = inline(text.attributedSubstring(from: content))
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append(escapeLineStart(line))
                }
            }
            location = NSMaxRange(lineRange)
        }
        return result
    }

    private struct Run { var text: String; var bold: Bool; var italic: Bool; var underline: Bool }

    /// One paragraph: adjacent runs with the same traits merged, emphasis
    /// markers placed inside surrounding whitespace so they stay valid.
    /// Markdown has no underline; `<u>…</u>` (inline HTML) is the convention.
    private static func inline(_ text: NSAttributedString) -> String {
        var runs: [Run] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            let font = attrs[.font] as? PlatformFont
            let run = Run(text: (text.string as NSString).substring(with: range),
                          bold: font?.isBoldTrait ?? false,
                          italic: font?.isItalicTrait ?? false,
                          underline: ((attrs[.underlineStyle] as? Int) ?? 0) != 0)
            if let last = runs.last, last.bold == run.bold, last.italic == run.italic, last.underline == run.underline {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }

        var out = ""
        for run in runs {
            let escaped = escapeInline(run.text)
            guard run.bold || run.italic || run.underline else { out += escaped; continue }
            // Whitespace at the edges goes outside the markers.
            let lead = escaped.prefix { $0.isWhitespace }
            let trail = escaped.reversed().prefix { $0.isWhitespace }
            let core = escaped.dropFirst(lead.count).dropLast(trail.count)
            guard !core.isEmpty else { out += escaped; continue }
            let marker = run.bold && run.italic ? "***" : (run.bold ? "**" : (run.italic ? "*" : ""))
            let open = run.underline ? "<u>" : "", close = run.underline ? "</u>" : ""
            out += String(lead) + open + marker + String(core) + marker + close + String(trail.reversed())
        }
        return out
    }

    /// Escape the few characters that would otherwise be read as emphasis or
    /// code when the text is imported again. Kept minimal so prose stays prose.
    private static func escapeInline(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\", "*", "_", "`": out.append("\\"); out.append(ch)
            default: out.append(ch)
            }
        }
        return out
    }

    /// A body line that starts like a heading, quote or rule must not become one.
    private static func escapeLineStart(_ line: String) -> String {
        guard let first = line.first else { return line }
        if first == "#" || first == ">" { return "\\" + line }
        if line.allSatisfy({ $0 == "-" || $0 == "=" }) && line.count >= 3 { return "\\" + line }
        return line
    }

    /// A comment may not contain "--"; soften it so the file stays valid.
    private static func commentSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "--", with: "—")
    }

    private static func formatted(_ size: Double) -> String {
        size == size.rounded() ? String(Int(size)) : String(size)
    }

    // MARK: - Import

    /// Everything a Markdown file gives a new document: the block tree and,
    /// if the file came from Kisho, the document font.
    static func document(from markdown: String) -> (sections: [KishoSection], typography: TypographySettings) {
        let typography = fontComment(in: markdown) ?? TypographySettings()
        return (sections(from: markdown, typography: typography), typography)
    }

    /// `<!-- kisho: font Family Name 14 -->` anywhere in the file.
    static func fontComment(in markdown: String) -> TypographySettings? {
        guard let range = markdown.range(of: "<!-- kisho: font ") else { return nil }
        let rest = markdown[range.upperBound...]
        guard let end = rest.range(of: "-->") else { return nil }
        let spec = rest[..<end.lowerBound].trimmingCharacters(in: .whitespaces)
        // Last token is the size; the family may contain spaces.
        guard let lastSpace = spec.lastIndex(of: " "),
              let size = Double(spec[spec.index(after: lastSpace)...]), size > 0 else { return nil }
        let family = String(spec[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        guard !family.isEmpty else { return nil }
        return TypographySettings(fontFamily: family, fontSize: size)
    }

    /// Parse Markdown into a block tree. Headings open blocks (depth from the
    /// heading level, nested under the nearest shallower heading); text
    /// before the first heading becomes a block with the default title.
    static func sections(from markdown: String, typography: TypographySettings = TypographySettings()) -> [KishoSection] {
        let base = typography.baseFont
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var roots: [KishoSection] = []
        // (section, heading level) from root to current.
        var stack: [(KishoSection, Int)] = []
        var current: KishoSection?
        var paragraphLines: [String] = []
        var bodyParagraphs: [NSAttributedString] = []
        var pendingTags: [String] = []
        var pendingStatus: BlockStatus?
        var pendingColour: Int?
        var pendingSynopsis = ""
        var pendingNotes = ""

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let joined = paragraphLines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            paragraphLines.removeAll()
            guard !joined.isEmpty else { return }
            bodyParagraphs.append(attributed(joined, base: base))
        }

        func closeBlock() {
            flushParagraph()
            guard let section = current else {
                // Text before any heading.
                if !bodyParagraphs.isEmpty {
                    let intro = KishoSection(title: KishoSection.defaultTitle)
                    intro.content.attributedString = join(bodyParagraphs)
                    roots.append(intro)
                }
                bodyParagraphs.removeAll()
                return
            }
            section.content.attributedString = join(bodyParagraphs)
            section.tags = pendingTags
            section.status = pendingStatus
            section.colorIndex = BlockPalette.isValid(pendingColour) ? pendingColour : nil
            section.synopsis = pendingSynopsis
            section.notes = pendingNotes
            bodyParagraphs.removeAll()
            pendingTags.removeAll()
            pendingStatus = nil; pendingColour = nil; pendingSynopsis = ""; pendingNotes = ""
        }

        func openBlock(title: String, level: Int) {
            closeBlock()
            let section = KishoSection(title: title.isEmpty ? KishoSection.defaultTitle : title)
            while let last = stack.last, last.1 >= level { stack.removeLast() }
            if let parent = stack.last?.0 {
                parent.children.append(section)
            } else {
                roots.append(section)
            }
            stack.append((section, level))
            current = section
        }

        var index = 0
        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // HTML comments: Kisho's own metadata, or anything else (dropped).
            // A comment may span lines (notes do).
            if line.hasPrefix("<!--") {
                var commentLines = [String(line.dropFirst(4))]
                var endIndex = index
                while !(commentLines.last ?? "").contains("-->"), endIndex + 1 < lines.count {
                    endIndex += 1
                    commentLines.append(lines[endIndex])
                }
                if let last = commentLines.last, let close = last.range(of: "-->") {
                    commentLines[commentLines.count - 1] = String(last[..<close.lowerBound])
                }
                let inner = commentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = inner.lowercased()
                if lower.hasPrefix("tags:") {
                    pendingTags = inner.dropFirst(5).split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                } else if lower.hasPrefix("kisho: status ") {
                    pendingStatus = BlockStatus(rawValue: inner.dropFirst(14).trimmingCharacters(in: .whitespaces).lowercased())
                } else if lower.hasPrefix("kisho: colour ") || lower.hasPrefix("kisho: color ") {
                    let digits = inner.split(separator: " ").last.map(String.init) ?? ""
                    pendingColour = Int(digits)
                } else if lower.hasPrefix("synopsis:") {
                    pendingSynopsis = inner.dropFirst(9).trimmingCharacters(in: .whitespaces)
                } else if lower.hasPrefix("notes:") {
                    pendingNotes = inner.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                flushParagraph()
                index = endIndex + 1
                continue
            }

            // ATX heading.
            if let (level, title) = atxHeading(line) {
                openBlock(title: title, level: level)
                index += 1
                continue
            }

            // Setext heading: a text line followed by === or ---.
            if !line.isEmpty, index + 1 < lines.count, paragraphLines.isEmpty,
               let level = setextLevel(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                openBlock(title: plain(line), level: level)
                index += 2
                continue
            }

            if line.isEmpty {
                flushParagraph()
            } else {
                paragraphLines.append(raw)
            }
            index += 1
        }
        closeBlock()

        return roots.isEmpty ? [KishoSection(title: KishoSection.defaultTitle)] : roots
    }

    private static func atxHeading(_ line: String) -> (Int, String)? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 6 { level += 1; rest = rest.dropFirst() }
        guard level > 0, rest.isEmpty || rest.first == " " else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        // Optional closing hashes: "## Title ##".
        while title.hasSuffix("#") { title.removeLast() }
        return (level, plain(title.trimmingCharacters(in: .whitespaces)))
    }

    private static func setextLevel(_ underline: String) -> Int? {
        guard underline.count >= 3 else { return nil }
        if underline.allSatisfy({ $0 == "=" }) { return 1 }
        if underline.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    /// Inline Markdown with emphasis and escapes removed (for titles).
    static func plain(_ s: String) -> String {
        attributed(s, base: PlatformFont.systemFont(ofSize: 12)).string
    }

    /// Inline parse: `***`/`**`/`*`/`__`/`_` toggle traits, `<u>`/`</u>`
    /// toggle underline, backslash escapes the next character, everything
    /// else is literal.
    static func attributed(_ s: String, base: PlatformFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var bold = false, italic = false, underline = false
        var buffer = ""
        let chars = Array(s)

        func flush() {
            guard !buffer.isEmpty else { return }
            var attrs: [NSAttributedString.Key: Any] = [.font: font(base, bold: bold, italic: italic),
                                                        .foregroundColor: PlatformColor.label]
            if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: buffer, attributes: attrs))
            buffer = ""
        }

        func tag(at index: Int, _ tag: String) -> Bool {
            let end = index + tag.count
            guard end <= chars.count else { return false }
            return String(chars[index..<end]).lowercased() == tag
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                buffer.append(chars[i + 1]); i += 2; continue
            }
            if c == "<" {
                if tag(at: i, "<u>") { flush(); underline = true; i += 3; continue }
                if tag(at: i, "</u>") { flush(); underline = false; i += 4; continue }
            }
            if c == "*" || c == "_" {
                var n = 1
                while i + n < chars.count, chars[i + n] == c, n < 3 { n += 1 }
                // Underscores inside a word (snake_case) are literal.
                let prevIsWord = i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                let nextIsWord = i + n < chars.count && (chars[i + n].isLetter || chars[i + n].isNumber)
                if c == "_" && prevIsWord && nextIsWord {
                    buffer.append(String(repeating: c, count: n)); i += n; continue
                }
                flush()
                switch n {
                case 3: bold.toggle(); italic.toggle()
                case 2: bold.toggle()
                default: italic.toggle()
                }
                i += n
                continue
            }
            buffer.append(c)
            i += 1
        }
        flush()
        return out
    }

    private static func font(_ base: PlatformFont, bold: Bool, italic: Bool) -> PlatformFont {
        base.addingTraits(bold: bold, italic: italic)
    }

    private static func join(_ paragraphs: [NSAttributedString]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, p) in paragraphs.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n", attributes: p.length > 0 ? p.attributes(at: 0, effectiveRange: nil) : [:])) }
            out.append(p)
        }
        return out
    }
}

#if os(macOS)
import UniformTypeIdentifiers

extension Markdown {
    /// File ▸ Import Markdown…: choose a file, parse it, and open the result
    /// as a new untitled document. The chosen file is only read.
    static func importIntoNewDocument() {
        DocumentImport.run(
            allowedTypes: [.markdownText, .plainText],
            message: "Choose a Markdown file. Its headings become blocks in a new document; the file itself is not changed."
        ) { url in
            let imported = document(from: try String(contentsOf: url))
            return (imported.sections, imported.typography)
        }
    }
}
#endif
