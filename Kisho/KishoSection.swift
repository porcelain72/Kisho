//
//  KishoSection.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine
import RichTextEditor

final class KishoSection: ObservableObject, Identifiable, Codable {
    // MARK: - Published properties (for SwiftUI bindings)
    @Published var title: String
    @Published var content: RichTextModel      // RTF‐encoded text
    /// Nested sections. Parent pointers are maintained automatically whenever
    /// this array is mutated, so callers never need to fix them up by hand.
    @Published var children: [KishoSection] {
        didSet { relinkChildren() }
    }
    @Published var tags : [String]
    // Planning metadata (see KishoBlockMetadata.swift). All optional in the
    // file so documents from before they existed still open.
    @Published var status: BlockStatus?
    /// Index into `BlockPalette`, or nil for no colour.
    @Published var colorIndex: Int?
    @Published var synopsis: String = ""
    @Published var notes: String = ""
    // NOTE: We do not store `parent` in the file; we rebuild it after decoding
    @Published var inspectorVersion : UUID = UUID()

    weak var parent: KishoSection?

    let id: UUID
    let createdAt: Date
    @Published var modifiedAt: Date

    static let defaultTitle = "Untitled"

    // MARK: - CodingKeys for Codable
    enum CodingKeys: String, CodingKey {
        case id, title, content, children, tags, createdAt, modifiedAt
        case status, colorIndex, synopsis, notes
    }

    // MARK: - Initializers
    init(
        id: UUID = UUID(),
        title: String,
        content: RichTextModel = RichTextModel(),
        children: [KishoSection] = [],
        tags: [String] = [],
        parent: KishoSection? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.children = children
        self.tags = tags
        self.parent = parent
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt

        // didSet does not fire from an initializer.
        relinkChildren()
    }

    // MARK: - Codable (encode/decode)
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self,   forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(RichTextModel.self,  forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        // Each child's own decoder init has already linked *its* children, so
        // only one level needs linking here.
        children = try container.decode([KishoSection].self, forKey: .children)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try container.decodeIfPresent(BlockStatus.self, forKey: .status)
        let colour = try container.decodeIfPresent(Int.self, forKey: .colorIndex)
        colorIndex = BlockPalette.isValid(colour) ? colour : nil
        synopsis = try container.decodeIfPresent(String.self, forKey: .synopsis) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""

        relinkChildren()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id,       forKey: .id)
        try container.encode(title,    forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt,   forKey: .createdAt)
        try container.encode(modifiedAt,  forKey: .modifiedAt)
        try container.encode(children,  forKey: .children)
        try container.encode(tags, forKey: .tags)
        // Only written when set, so untouched documents don't change shape.
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(colorIndex, forKey: .colorIndex)
        if !synopsis.isEmpty { try container.encode(synopsis, forKey: .synopsis) }
        if !notes.isEmpty { try container.encode(notes, forKey: .notes) }
    }

    private func relinkChildren() {
        for child in children where child.parent !== self {
            child.parent = self
        }
    }

    /// First line of `title` (section headings are a single line). Extra lines are
    /// treated as body text that was typed into the heading in the composite editor.
    var titleFirstLine: String {
        title.components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? title
    }

    /// Title to show in lists and headings: the first title line, or a title
    /// derived from the content when the section has no title of its own.
    var displayTitle: String {
        let first = titleFirstLine
        if !first.isEmpty { return first }
        return content.defaultTitle
    }

    /// Whether `other` is this section or one of its descendants.
    func contains(sectionID other: UUID) -> Bool {
        if id == other { return true }
        return children.contains { $0.contains(sectionID: other) }
    }

    /// Pre-order list of this section and all of its descendants.
    var subtree: [KishoSection] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.subtree)
        }
        return result
    }

    /// Splits this section's body into one new section per paragraph. Each
    /// new section is named after the paragraph's first sentence and carries
    /// the full paragraph, with its formatting, as its body.
    func asSections() -> [KishoSection] {
        KishoSection.paragraphModelsForSplit(section: self)
            .map { paragraph in
                let body = RichTextModel()
                body.attributedString = KishoSection.trimmedParagraph(paragraph.attributedString)
                return KishoSection(title: body.defaultTitle, content: body)
            }
    }

    /// Removes leading/trailing whitespace and paragraph breaks from a paragraph
    /// while keeping its attributes.
    static func trimmedParagraph(_ source: NSAttributedString) -> NSAttributedString {
        let ns = source.string as NSString
        var start = 0
        var end = ns.length
        let ws = CharacterSet.whitespacesAndNewlines
        while start < end,
              let scalar = Unicode.Scalar(ns.character(at: start)),
              ws.contains(scalar) {
            start += 1
        }
        while end > start,
              let scalar = Unicode.Scalar(ns.character(at: end - 1)),
              ws.contains(scalar) {
            end -= 1
        }
        guard end > start else { return NSAttributedString() }
        return source.attributedSubstring(from: NSRange(location: start, length: end - start))
    }

    func copyDeep(parent: KishoSection? = nil) -> KishoSection {
        let sectionCopy = KishoSection(
            id: self.id,
            title: self.title,
            content: self.content.copy(),
            children: [], // we'll fill this in below
            tags: self.tags,
            parent: parent,
            createdAt: self.createdAt,
            modifiedAt: self.modifiedAt
        )

        // Recursively copy children
        sectionCopy.children = self.children.map {
            $0.copyDeep(parent: sectionCopy)
        }

        return sectionCopy
    }

    /// This section's body followed by the bodies of every descendant, in
    /// reading order, separated by paragraph breaks. Empty bodies are skipped.
    func joinedChildrenContent() -> RichTextModel {
        let parts = subtree
            .map { $0.content }
            .filter { !$0.attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return RichTextModel.joined(parts)
    }


    // MARK: - Word Count

    private var wordCountCache: (text: NSAttributedString, count: Int)?

    /// Word count for this section's own content only. Cached per content
    /// object so a document-wide total is cheap to recompute while typing.
    var wordCount: Int {
        let attributed = content.attributedString
        if let cache = wordCountCache, cache.text === attributed { return cache.count }
        let text = attributed.string
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        wordCountCache = (attributed, count)
        return count
    }

    /// Aggregate word count: this section's content plus all descendants.
    var totalWordCount: Int {
        children.reduce(wordCount) { $0 + $1.totalWordCount }
    }

    func applyTypographyToSelfAndDescendants(font: PlatformFont, color: PlatformColor? = nil) {
        // Apply to this section, keeping any bold/italic the writer applied to runs.
        self.content.attributedString = KishoSection.retypeset(content.attributedString, base: font, color: color)

        // Recursively apply to children
        for child in children {
            child.applyTypographyToSelfAndDescendants(font: font, color: color)
        }

        // Trigger UI updates if needed
        self.inspectorVersion = UUID()
    }

}

extension KishoSection {
    /// Re-sets every run to `base` (family/size) while preserving each run's
    /// bold/italic traits, and optionally forces a colour.
    static func retypeset(_ source: NSAttributedString, base: PlatformFont, color: PlatformColor?) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)
        guard full.length > 0 else { return result }
        result.beginEditing()
        result.enumerateAttribute(.font, in: full) { value, range, _ in
            var font = base
            if let old = value as? PlatformFont {
                font = font.addingTraits(bold: old.isBoldTrait, italic: old.isItalicTrait)
            }
            result.addAttribute(.font, value: font, range: range)
        }
        if let color {
            result.addAttribute(.foregroundColor, value: color, range: full)
        }
        result.endEditing()
        return result
    }

    static func combinedRichText(from sections: [KishoSection]) -> RichTextModel {
        let richParts = sections.map { $0.joinedChildrenContent() }
        return RichTextModel.joined(richParts)
    }
}
