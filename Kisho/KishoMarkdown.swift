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
import AppKit
import RichTextEditor

enum Markdown {

    // MARK: - Export

    static func string(from sections: [KishoSection]) -> String {
        var out: [String] = []
        func walk(_ list: [KishoSection], depth: Int) {
            for section in list {
                out.append(String(repeating: "#", count: min(depth, 6)) + " " + escapeInline(section.displayTitle))
                if !section.tags.isEmpty {
                    out.append("<!-- tags: " + section.tags.joined(separator: ", ") + " -->")
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

    private struct Run { var text: String; var bold: Bool; var italic: Bool }

    /// One paragraph: adjacent runs with the same traits merged, emphasis
    /// markers placed inside surrounding whitespace so they stay valid.
    private static func inline(_ text: NSAttributedString) -> String {
        var runs: [Run] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let traits = (value as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let run = Run(text: (text.string as NSString).substring(with: range),
                          bold: traits.contains(.boldFontMask),
                          italic: traits.contains(.italicFontMask))
            if let last = runs.last, last.bold == run.bold, last.italic == run.italic {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }

        var out = ""
        for run in runs {
            let escaped = escapeInline(run.text)
            guard run.bold || run.italic else { out += escaped; continue }
            // Whitespace at the edges goes outside the markers.
            let lead = escaped.prefix { $0.isWhitespace }
            let trail = escaped.reversed().prefix { $0.isWhitespace }
            let core = escaped.dropFirst(lead.count).dropLast(trail.count)
            guard !core.isEmpty else { out += escaped; continue }
            let marker = run.bold && run.italic ? "***" : (run.bold ? "**" : "*")
            out += String(lead) + marker + String(core) + marker + String(trail.reversed())
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

    // MARK: - Import

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
            bodyParagraphs.removeAll()
            pendingTags.removeAll()
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

            // Tags comment (Kisho export) or any other HTML comment on its own line.
            if line.hasPrefix("<!--"), line.hasSuffix("-->") {
                let inner = line.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
                if inner.lowercased().hasPrefix("tags:") {
                    pendingTags = inner.dropFirst(5).split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
                flushParagraph()
                index += 1
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
        attributed(s, base: NSFont.systemFont(ofSize: 12)).string
    }

    /// Inline parse: `***`/`**`/`*`/`__`/`_` toggle traits, backslash escapes
    /// the next character, everything else is literal.
    static func attributed(_ s: String, base: NSFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var bold = false, italic = false
        var buffer = ""
        let chars = Array(s)

        func flush() {
            guard !buffer.isEmpty else { return }
            out.append(NSAttributedString(string: buffer, attributes: [.font: font(base, bold: bold, italic: italic),
                                                                       .foregroundColor: NSColor.labelColor]))
            buffer = ""
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                buffer.append(chars[i + 1]); i += 2; continue
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

    private static func font(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var font = base
        let manager = NSFontManager.shared
        if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
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
