//
//  KishoSection+Composite.swift
//  Kisho
//

import Foundation
import RichTextEditor

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    static let kishoSectionID = NSAttributedString.Key("kishoSectionID")
    static let kishoSectionRole = NSAttributedString.Key("kishoSectionRole")
    static let kishoSectionDepth = NSAttributedString.Key("kishoSectionDepth")
}

enum KishoSectionRole: String {
    case title
    case content
}

struct SubtreeSnapshot {
    struct SectionState {
        var title: String
        var content: RichTextModel
    }

    var states: [UUID: SectionState]
}

extension KishoSection {

    // MARK: - Document-level compose / distribute

    /// Composes every top-level section and its descendants into one editable
    /// attributed string, each section shown as a titled block.
    static func documentCompositeAttributedString(sections: [KishoSection]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for section in sections {
            section.appendBlock(relativeDepth: 0, to: result)
        }
        trimTrailingParagraphBreaks(result)
        return result
    }

    /// Distributes an edited document composite back into every section.
    static func applyDocumentComposite(_ composite: NSAttributedString, to sections: [KishoSection]) {
        let parsed = parseComposite(composite)
        for section in sections {
            section.applyParsed(titleParts: parsed.titles, contentParts: parsed.contents)
        }
    }

    static func documentSnapshot(of sections: [KishoSection]) -> SubtreeSnapshot {
        var states: [UUID: SubtreeSnapshot.SectionState] = [:]
        func collect(_ section: KishoSection) {
            states[section.id] = SubtreeSnapshot.SectionState(
                title: section.title,
                content: section.content.copy()
            )
            section.children.forEach(collect)
        }
        sections.forEach(collect)
        return SubtreeSnapshot(states: states)
    }

    static func applyDocumentSnapshot(_ snapshot: SubtreeSnapshot, to sections: [KishoSection]) {
        func apply(_ section: KishoSection) {
            if let state = snapshot.states[section.id] {
                section.title = state.title
                section.content.attributedString = state.content.attributedString
            }
            section.children.forEach(apply)
            section.modifiedAt = Date()
        }
        sections.forEach(apply)
    }

    /// Character range of a section's heading within a composite, used for scrolling.
    static func compositeRange(forSectionID id: UUID, in composite: NSAttributedString) -> NSRange? {
        let target = id.uuidString
        var index = 0
        while index < composite.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = composite.attributes(at: index, effectiveRange: &effectiveRange)
            // Title run only: enumerating the ID attribute alone would merge the
            // heading with the body run that follows it (same ID value).
            if let value = attrs[.kishoSectionID] as? String, value == target,
               let role = attrs[.kishoSectionRole] as? String,
               role == KishoSectionRole.title.rawValue {
                return effectiveRange
            }
            index = effectiveRange.location + effectiveRange.length
        }
        return nil
    }

    /// Caret position at the end of a section's own content (after its body, before
    /// any child heading). Falls back to the end of the heading when content is empty.
    static func compositeCaretIndex(forSectionID id: UUID, in composite: NSAttributedString) -> Int? {
        let target = id.uuidString
        var contentEnd: Int?
        var titleEnd: Int?

        var index = 0
        while index < composite.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = composite.attributes(at: index, effectiveRange: &effectiveRange)
            if let value = attrs[.kishoSectionID] as? String, value == target,
               let roleString = attrs[.kishoSectionRole] as? String {
                let end = effectiveRange.location + effectiveRange.length
                if roleString == KishoSectionRole.content.rawValue {
                    contentEnd = max(contentEnd ?? 0, end)
                } else if roleString == KishoSectionRole.title.rawValue {
                    titleEnd = max(titleEnd ?? 0, end)
                }
            }
            index = effectiveRange.location + effectiveRange.length
        }

        if let contentEnd, contentEnd > 0 {
            return clampedCaretIndex(contentEnd, in: composite)
        }
        if let titleEnd, titleEnd > 0 {
            return clampedCaretIndex(titleEnd, in: composite)
        }
        return titleEnd
    }

    /// Avoid sitting after a trailing paragraph break, which NSTextView draws as
    /// an empty line below the last section.
    fileprivate static func clampedCaretIndex(_ end: Int, in composite: NSAttributedString) -> Int {
        guard end > 0, end <= composite.length else { return max(0, min(end, composite.length)) }
        let last = (composite.string as NSString).substring(with: NSRange(location: end - 1, length: 1))
        if last == "\n" || last == "\r" {
            return end - 1
        }
        return end
    }

    /// Body text of a section in a composite: everything after that section's
    /// heading until the next heading (child or sibling). Includes untagged
    /// runs that NSTextView inserted without ownership attributes.
    static func compositeBody(forSectionID id: UUID, in composite: NSAttributedString) -> NSAttributedString {
        let target = id.uuidString
        var titleEnd: Int?
        var nextTitleStart: Int?

        var index = 0
        while index < composite.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = composite.attributes(at: index, effectiveRange: &effectiveRange)
            if let value = attrs[.kishoSectionID] as? String,
               let roleString = attrs[.kishoSectionRole] as? String,
               roleString == KishoSectionRole.title.rawValue {
                let end = effectiveRange.location + effectiveRange.length
                if value == target {
                    titleEnd = max(titleEnd ?? 0, end)
                } else if let titleEnd, effectiveRange.location >= titleEnd {
                    nextTitleStart = effectiveRange.location
                    break
                }
            }
            index = effectiveRange.location + effectiveRange.length
        }

        guard let start = titleEnd else { return NSAttributedString() }
        let end = nextTitleStart ?? composite.length
        guard end > start else { return NSAttributedString() }
        return composite.attributedSubstring(from: NSRange(location: start, length: end - start))
    }

    /// Paragraphs that Split should turn into child sections.
    static func paragraphModelsForSplit(
        section: KishoSection,
        composite: NSAttributedString?
    ) -> [RichTextModel] {
        let merged = NSMutableAttributedString()

        let titleSource: String
        if let composite {
            titleSource = titleString(forSectionID: section.id, in: composite) ?? section.title
        } else {
            titleSource = section.title
        }
        let extraTitleLines = titleSource
            .components(separatedBy: .newlines)
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !extraTitleLines.isEmpty {
            merged.append(NSAttributedString(string: extraTitleLines + "\n"))
        }

        if let composite {
            merged.append(stripOwnershipAttributes(from: compositeBody(forSectionID: section.id, in: composite)))
        } else {
            merged.append(section.content.attributedString)
        }

        return splitParagraphs(from: merged)
    }

    static func splitParagraphs(from source: NSAttributedString) -> [RichTextModel] {
        let ns = source.string as NSString
        var parts: [RichTextModel] = []
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: .byLines
        ) { _, substringRange, _, _ in
            guard substringRange.length > 0 else { return }
            let sub = source.attributedSubstring(from: substringRange)
            let trimmed = sub.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let model = RichTextModel()
            model.attributedString = sub
            parts.append(model)
        }
        return parts
    }

    fileprivate static func titleString(forSectionID id: UUID, in composite: NSAttributedString) -> String? {
        let target = id.uuidString
        var title = ""
        var index = 0
        while index < composite.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = composite.attributes(at: index, effectiveRange: &effectiveRange)
            if let value = attrs[.kishoSectionID] as? String, value == target,
               let role = attrs[.kishoSectionRole] as? String,
               role == KishoSectionRole.title.rawValue {
                title += composite.attributedSubstring(from: effectiveRange).string
            }
            index = effectiveRange.location + effectiveRange.length
        }
        return title.isEmpty ? nil : title
    }

    static func allSections(in sections: [KishoSection]) -> [KishoSection] {
        var result: [KishoSection] = []
        func collect(_ section: KishoSection) {
            result.append(section)
            section.children.forEach(collect)
        }
        sections.forEach(collect)
        return result
    }

    // MARK: - Per-section compose (selected subtree, root title lives elsewhere)

    func compositeAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        appendTaggedContent(
            from: content.attributedString,
            sectionID: id,
            role: .content,
            relativeDepth: 0,
            to: result
        )
        for child in children {
            child.appendBlock(relativeDepth: 1, to: result)
        }
        return result
    }

    func applyCompositeAttributedString(_ composite: NSAttributedString) {
        let parsed = KishoSection.parseComposite(composite)
        applyParsedSubtree(titleParts: parsed.titles, contentParts: parsed.contents, isRoot: true)
        modifiedAt = Date()
    }

    func subtreeSnapshot() -> SubtreeSnapshot {
        KishoSection.documentSnapshot(of: [self])
    }

    func applySnapshot(_ snapshot: SubtreeSnapshot) {
        KishoSection.applyDocumentSnapshot(snapshot, to: [self])
    }

    // MARK: - Shared building blocks

    /// Emits this section as a titled block: heading + body, then children recursively.
    fileprivate func appendBlock(relativeDepth: Int, to result: NSMutableAttributedString) {
        if result.length > 0 {
            result.append(KishoSection.sectionBreak())
        }

        let titleLines = title.components(separatedBy: .newlines)
        let headingText: String = {
            let first = titleLines.first?.trimmingCharacters(in: .whitespaces) ?? ""
            if !first.isEmpty { return first }
            return title.isEmpty ? content.defaultTitle : titleFirstLine
        }()
        let titleAttrs = KishoSection.headingAttributes(relativeDepth: relativeDepth, sectionID: id)
        result.append(NSAttributedString(string: headingText, attributes: titleAttrs))
        // End the heading paragraph so the wash stays on the title only.
        result.append(NSAttributedString(string: "\n", attributes: titleAttrs))

        let extraTitleLines = titleLines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let body = content.attributedString
        if !extraTitleLines.isEmpty {
            appendTaggedContent(
                from: NSAttributedString(string: extraTitleLines),
                sectionID: id,
                role: .content,
                relativeDepth: relativeDepth,
                to: result
            )
        }
        if !KishoSection.isVisuallyEmpty(body) {
            if result.length > 0,
               !KishoSection.lastCharacter(of: result).isNewline {
                result.append(NSAttributedString(string: "\n", attributes: KishoSection.bodyBreakAttributes(relativeDepth: relativeDepth, sectionID: id)))
            }
            appendTaggedContent(
                from: body,
                sectionID: id,
                role: .content,
                relativeDepth: relativeDepth,
                to: result
            )
        } else if extraTitleLines.isEmpty {
            // One content-tagged space on the line below the heading so typing
            // stays in the body, without a second washed paragraph.
            appendTaggedContent(
                from: NSAttributedString(string: " "),
                sectionID: id,
                role: .content,
                relativeDepth: relativeDepth,
                to: result
            )
        }

        for child in children {
            child.appendBlock(relativeDepth: relativeDepth + 1, to: result)
        }
    }

    fileprivate func appendTaggedContent(
        from source: NSAttributedString,
        sectionID: UUID,
        role: KishoSectionRole,
        relativeDepth: Int,
        to result: NSMutableAttributedString
    ) {
        guard source.length > 0 else { return }
        let tagged = NSMutableAttributedString(attributedString: source)
        let range = NSRange(location: 0, length: tagged.length)
        tagged.addAttribute(.kishoSectionID, value: sectionID.uuidString, range: range)
        tagged.addAttribute(.kishoSectionRole, value: role.rawValue, range: range)
        tagged.addAttribute(.kishoSectionDepth, value: relativeDepth, range: range)
        // Force an appearance-adaptive text color so body text (and text typed
        // adjacent to it) follows light/dark mode rather than any baked-in color.
        #if os(macOS)
        tagged.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        #else
        tagged.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        #endif
        KishoSection.applySectionChrome(to: tagged, relativeDepth: relativeDepth, isTitle: role == .title)
        result.append(tagged)
    }

    fileprivate static func lastCharacter(of text: NSAttributedString) -> Character {
        guard text.length > 0 else { return "\0" }
        let ns = text.string as NSString
        let end = ns.rangeOfComposedCharacterSequence(at: ns.length - 1)
        let s = ns.substring(with: end)
        return s.first ?? "\0"
    }

    fileprivate static func trimTrailingParagraphBreaks(_ text: NSMutableAttributedString) {
        while text.length > 0 {
            let ch = lastCharacter(of: text)
            if ch == "\n" || ch == "\r" {
                let ns = text.string as NSString
                let end = ns.rangeOfComposedCharacterSequence(at: ns.length - 1)
                text.deleteCharacters(in: end)
            } else {
                break
            }
        }
    }

    /// Empty unstyled paragraph between sections so heading washes cannot merge.
    fileprivate static func sectionBreak() -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.textBlocks = []
        para.headIndent = 0
        para.firstLineHeadIndent = 0
        para.paragraphSpacingBefore = 8
        para.paragraphSpacing = 4
        para.minimumLineHeight = 10
        para.maximumLineHeight = 12
        // Line height is pinned by the paragraph style, so a normal-size font
        // keeps the gap the same but stops text accidentally typed into the gap
        // from appearing microscopic.
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 12)
        #else
        let font = UIFont.systemFont(ofSize: 12)
        #endif
        // No foreground colour: paragraph breaks draw nothing, and leaving the
        // attribute out keeps the composite equal to what the text view shows
        // after its display-colour pass, so rebuilds don't needlessly reset it.
        return NSAttributedString(string: "\n\n", attributes: [
            .paragraphStyle: para,
            .font: font
        ])
    }

    fileprivate static func bodyBreakAttributes(relativeDepth: Int, sectionID: UUID) -> [NSAttributedString.Key: Any] {
        [
            .paragraphStyle: sectionParagraphStyle(relativeDepth: relativeDepth, isTitle: false),
            .kishoSectionID: sectionID.uuidString,
            .kishoSectionRole: KishoSectionRole.content.rawValue,
            .kishoSectionDepth: relativeDepth
        ]
    }

    fileprivate static func isVisuallyEmpty(_ text: NSAttributedString) -> Bool {
        guard text.length > 0 else { return true }
        return text.string.unicodeScalars.allSatisfy { scalar in
            scalar == "\u{2028}" || scalar == "\u{2029}" || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }

    fileprivate static let sectionIndentStep: CGFloat = 20

    fileprivate static func headingAttributes(relativeDepth: Int, sectionID: UUID) -> [NSAttributedString.Key: Any] {
        let fontSize: CGFloat
        switch relativeDepth {
        case 0: fontSize = 20
        case 1: fontSize = 18
        case 2: fontSize = 16
        default: fontSize = 14
        }

        #if os(macOS)
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let color = NSColor.labelColor
        #else
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let color = UIColor.label
        #endif

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: sectionParagraphStyle(relativeDepth: relativeDepth, isTitle: true),
            .kishoSectionID: sectionID.uuidString,
            .kishoSectionRole: KishoSectionRole.title.rawValue,
            .kishoSectionDepth: relativeDepth
        ]
    }

    fileprivate static func applySectionChrome(
        to text: NSMutableAttributedString,
        relativeDepth: Int,
        isTitle: Bool
    ) {
        var index = 0
        while index < text.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let existing = text.attribute(.paragraphStyle, at: index, effectiveRange: &effectiveRange) as? NSParagraphStyle
            let style = sectionParagraphStyle(
                relativeDepth: relativeDepth,
                isTitle: isTitle,
                base: existing
            )
            text.addAttribute(.paragraphStyle, value: style, range: effectiveRange)
            index = effectiveRange.location + effectiveRange.length
        }
    }

    fileprivate static func sectionParagraphStyle(
        relativeDepth: Int,
        isTitle: Bool,
        base: NSParagraphStyle? = nil
    ) -> NSMutableParagraphStyle {
        let para = (base?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let indent = CGFloat(relativeDepth) * sectionIndentStep
        // Indent the card (text block margin), not the text inside it.
        para.firstLineHeadIndent = 0
        para.headIndent = 0
        // Flush heading against body so they read as one card; sectionBreak
        // supplies the gap between cards.
        para.paragraphSpacingBefore = 0
        para.paragraphSpacing = 0
        para.textBlocks = sectionTextBlocks(relativeDepth: relativeDepth, isTitle: isTitle)
        return para
    }

    /// One plain NSTextBlock per paragraph: a left margin insets nested cards.
    /// (An earlier version nested two cells of the same NSTextTable inside each
    /// other to fake a gutter; TextKit cannot lay that out and stopped drawing
    /// at the first nested section.) No explicit width is set, so the block
    /// fills the container minus its margins.
    fileprivate static func sectionTextBlocks(relativeDepth: Int, isTitle: Bool) -> [NSTextBlock] {
        [sectionCardBlock(relativeDepth: relativeDepth, isTitle: isTitle)]
    }

    fileprivate static func sectionCardBlock(relativeDepth: Int, isTitle: Bool) -> NSTextBlock {
        let indent = CGFloat(relativeDepth) * sectionIndentStep
        let card = NSTextBlock()
        card.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX)
        card.setWidth(0, type: .absoluteValueType, for: .margin, edge: .maxX)
        card.setWidth(0, type: .absoluteValueType, for: .margin, edge: .minY)
        card.setWidth(0, type: .absoluteValueType, for: .margin, edge: .maxY)
        card.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
        card.setWidth(10, type: .absoluteValueType, for: .padding, edge: .maxX)
        card.setWidth(isTitle ? 7 : 8, type: .absoluteValueType, for: .padding, edge: .minY)
        card.setWidth(isTitle ? 7 : 8, type: .absoluteValueType, for: .padding, edge: .maxY)
        card.setWidth(4, type: .absoluteValueType, for: .border, edge: .minX)
        card.setBorderColor(sectionAccentColor(relativeDepth: relativeDepth), for: .minX)
        card.backgroundColor = sectionFillColor(relativeDepth: relativeDepth, isTitle: isTitle)
        return card
    }

    #if os(macOS)
    fileprivate static func sectionAccentColor(relativeDepth: Int) -> NSColor {
        let hue = (0.55 + CGFloat(relativeDepth) * 0.08).truncatingRemainder(dividingBy: 1.0)
        return NSColor(calibratedHue: hue, saturation: 0.50, brightness: 0.62, alpha: 0.90)
    }

    fileprivate static func sectionFillColor(relativeDepth: Int, isTitle: Bool) -> NSColor {
        let hue = (0.55 + CGFloat(relativeDepth) * 0.08).truncatingRemainder(dividingBy: 1.0)
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua) ?? NSAppearance()
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isTitle {
            let brightness: CGFloat = isDark ? 0.34 : 0.86
            return NSColor(calibratedHue: hue, saturation: 0.28, brightness: brightness, alpha: 0.88)
        } else {
            let brightness: CGFloat = isDark ? 0.22 : 0.96
            return NSColor(calibratedHue: hue, saturation: 0.10, brightness: brightness, alpha: 0.62)
        }
    }
    #else
    fileprivate static func sectionAccentColor(relativeDepth: Int) -> UIColor {
        UIColor(
            hue: (0.55 + CGFloat(relativeDepth) * 0.08).truncatingRemainder(dividingBy: 1.0),
            saturation: 0.40,
            brightness: 0.72,
            alpha: 0.55
        )
    }

    fileprivate static func sectionFillColor(relativeDepth: Int, isTitle: Bool) -> UIColor {
        if isTitle {
            return UIColor.secondarySystemBackground
        } else {
            return UIColor.tertiarySystemBackground
        }
    }
    #endif

    fileprivate static func parseComposite(
        _ composite: NSAttributedString
    ) -> (titles: [UUID: String], contents: [UUID: NSMutableAttributedString]) {
        var titleParts: [UUID: String] = [:]
        var contentParts: [UUID: NSMutableAttributedString] = [:]
        var lastSectionID: UUID?

        func appendContent(_ id: UUID, _ substring: NSAttributedString) {
            let stripped = stripOwnershipAttributes(from: substring)
            let bucket = contentParts[id] ?? NSMutableAttributedString()
            bucket.append(stripped)
            contentParts[id] = bucket
        }

        var index = 0
        while index < composite.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = composite.attributes(at: index, effectiveRange: &effectiveRange)
            let substring = composite.attributedSubstring(from: effectiveRange)

            if let idString = attrs[.kishoSectionID] as? String,
               let sectionID = UUID(uuidString: idString),
               let roleString = attrs[.kishoSectionRole] as? String,
               let role = KishoSectionRole(rawValue: roleString) {
                switch role {
                case .title:
                    titleParts[sectionID, default: ""] += substring.string
                case .content:
                    appendContent(sectionID, substring)
                }
                lastSectionID = sectionID
            } else if let lastSectionID {
                let next = nextTaggedRole(in: composite, startingAt: effectiveRange.location + effectiveRange.length)
                let onlyWhitespace = substring.string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                // Drop whitespace that only separates this block from the next heading.
                // Keep everything else — NSTextView often inserts new paragraphs without
                // our ownership attributes, and those must remain in the body.
                if !(onlyWhitespace && next == .title) {
                    appendContent(lastSectionID, substring)
                }
            }

            index = effectiveRange.location + effectiveRange.length
        }

        return (titleParts, contentParts)
    }

    fileprivate static func nextTaggedRole(
        in composite: NSAttributedString,
        startingAt location: Int
    ) -> KishoSectionRole? {
        var index = location
        while index < composite.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = composite.attributes(at: index, effectiveRange: &effectiveRange)
            if let roleString = attrs[.kishoSectionRole] as? String,
               let role = KishoSectionRole(rawValue: roleString) {
                return role
            }
            index = effectiveRange.location + effectiveRange.length
        }
        return nil
    }

    /// Applies parsed data to this section + descendants, treating every node as titled.
    fileprivate func applyParsed(
        titleParts: [UUID: String],
        contentParts: [UUID: NSMutableAttributedString]
    ) {
        applyParsedSubtree(titleParts: titleParts, contentParts: contentParts, isRoot: false)
    }

    private func applyParsedSubtree(
        titleParts: [UUID: String],
        contentParts: [UUID: NSMutableAttributedString],
        isRoot: Bool
    ) {
        func apply(_ section: KishoSection, isRoot: Bool) {
            // Root of a per-section composite keeps its title (edited via the title field).
            var extraTitleBody = ""
            if !isRoot {
                let rawTitle = titleParts[section.id] ?? ""
                let titleLines = rawTitle.components(separatedBy: .newlines)
                let firstLine = titleLines.first?.trimmingCharacters(in: .whitespaces) ?? ""
                extraTitleBody = titleLines.dropFirst()
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                if !firstLine.isEmpty {
                    if section.title != firstLine { section.title = firstLine }
                } else if let content = contentParts[section.id], content.length > 0 {
                    let model = RichTextModel()
                    model.attributedString = KishoSection.stripOwnershipAttributes(from: content)
                    let derived = model.defaultTitle
                    if section.title != derived { section.title = derived }
                }
            }

            if let content = contentParts[section.id] {
                let stripped = KishoSection.stripOwnershipAttributes(from: content)
                if extraTitleBody.isEmpty && KishoSection.isVisuallyEmpty(stripped) {
                    section.content.attributedString = NSAttributedString(string: "")
                } else if extraTitleBody.isEmpty {
                    section.content.attributedString = stripped
                } else {
                    let merged = NSMutableAttributedString(string: extraTitleBody)
                    if !KishoSection.isVisuallyEmpty(stripped) {
                        merged.append(NSAttributedString(string: "\n"))
                        merged.append(stripped)
                    }
                    section.content.attributedString = merged
                }
            } else if !extraTitleBody.isEmpty {
                section.content.attributedString = NSAttributedString(string: extraTitleBody)
            } else if !isRoot {
                section.content.attributedString = NSAttributedString(string: "")
            }

            section.children.forEach { apply($0, isRoot: false) }
        }

        apply(self, isRoot: isRoot)
    }

    fileprivate static func stripOwnershipAttributes(from source: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: source)
        let range = NSRange(location: 0, length: mutable.length)
        guard range.length > 0 else { return mutable }

        var index = 0
        while index < mutable.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = mutable.attributes(at: index, effectiveRange: &effectiveRange)
            if let para = attrs[.paragraphStyle] as? NSParagraphStyle {
                let copy = para.mutableCopy() as! NSMutableParagraphStyle
                copy.textBlocks = []
                copy.paragraphSpacingBefore = 0
                copy.paragraphSpacing = 0
                mutable.addAttribute(.paragraphStyle, value: copy, range: effectiveRange)
            }
            index = effectiveRange.location + effectiveRange.length
        }

        mutable.removeAttribute(.kishoSectionID, range: range)
        mutable.removeAttribute(.kishoSectionRole, range: range)
        mutable.removeAttribute(.kishoSectionDepth, range: range)
        return mutable
    }
}
