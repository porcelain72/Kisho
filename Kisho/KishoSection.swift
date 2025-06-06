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

final class KishoSection: ObservableObject, Identifiable, Codable {
    // MARK: - Published properties (for SwiftUI bindings)
    @Published var title: String
    @Published var content: KishoRichText       // RTF‐encoded text
    @Published var children: [KishoSection] // nested sections
    @Published var tags : [String]
    // NOTE: We do not store `parent` in the file; we rebuild it after decoding
    @Published var inspectorVersion : UUID = UUID()
    
    weak var parent: KishoSection?
    
    let id: UUID
    let createdAt: Date
    @Published var modifiedAt: Date

    // MARK: - CodingKeys for Codable
    enum CodingKeys: String, CodingKey {
        case id, title, content, children, tags, createdAt, modifiedAt
    }
    
    // MARK: - Initializers
    init(
        id: UUID = UUID(),
        title: String,
        content: KishoRichText = KishoRichText(rtfData: NSAttributedString(string: "").rtfData()) ,
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
        
        // Hook each child’s parent pointer
        for child in children {
            child.parent = self
        }
    }
    
    // MARK: - Codable (encode/decode)
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self,   forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(KishoRichText.self,  forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        // First decode children as an array of KishoSection
        let decodedChildren = try container.decode([KishoSection].self, forKey: .children)
        
        // Now set published children and re‐establish parent links
        children = decodedChildren
        self.tags = try container.decode([String].self, forKey: .tags)      // ← decode tags

        for child in children {
             child.parent = self
             // Also recursively fix up the grandchildren
             func fixDescendants(of node: KishoSection) {
                 for sub in node.children {
                     sub.parent = node
                     fixDescendants(of: sub)
                 }
             }
             fixDescendants(of: child)
         }
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
    }
    
    
    func asSections() -> [KishoSection] {
        
        var secs : [KishoSection]  = []
        
        let paras = self.content.paragraphs()
        
        paras.forEach { paragraph in
            let newSection = KishoSection(title: paragraph.defaultTitle, content: paragraph)
            secs.append(newSection)
        }
        
        return secs
        
    }
    
    func joinedChildrenContent() -> KishoRichText {
        return KishoRichText.fromSections(self.children)
    }
   /*
    // MARK: - Helpers for Rich Text
    var attributedText: NSAttributedString {
        get { NSAttributedString.fromRTF(data: richTextData) ?? .init(string: "") }
        set { richTextData = newValue.rtfData() }
    }
    */
}


/// A wrapper around NSAttributedString that exposes `@Published var attributedString`
/// and makes the type `Codable` by round-tripping through RTF data.
final class KishoRichText: ObservableObject, Codable {
    // MARK: –– Published attributed string
    @Published var attributedString: NSAttributedString

    // MARK: –– Designated initializers

  //  var attributes : [NSAttributedString.Key:Any] = [:]
    /// Create an empty KishoRichText (i.e. an empty string).
    init() {
        self.attributedString = NSAttributedString(string: "")
    }

    /// Create from existing RTF data.
    /// If the data cannot be decoded, falls back to an empty string.
    init(rtfData: Data) {
        if let decoded = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            self.attributedString = decoded
        } else {
            self.attributedString = NSAttributedString(string: "")
        }
    }

    // MARK: –– Codable Conformance

    enum CodingKeys: String, CodingKey {
        case rtfData
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: .rtfData)

        if let decoded = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            self.attributedString = decoded
        } else {
            self.attributedString = NSAttributedString(string: "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rtfData = attributedString.rtfData()
        try container.encode(rtfData, forKey: .rtfData)
    }
    
    func flushContent()  {
        self.attributedString = NSAttributedString(string: "")
    }
}



extension KishoRichText {
    
    /// Create a single KishoRichText by concatenating the `content` of each KishoSection in order.
    /// Inserts one newline between each section’s content, preserving all attributes.
    static func fromSections(_ sections: [KishoSection]) -> KishoRichText {
        // 1) Extract each section’s KishoRichText
        let richParts = sections.map { $0.content }

        // 2) Reuse the joined(_:) helper to concatenate them
        return KishoRichText.joined(richParts)
    }
    
    /// Splits `self.attributedString` into paragraphs, returning each paragraph
    /// as a brand‐new `KishoRichText` (with its own attributed string).
    ///
    /// Paragraph boundaries are determined using NSString’s `.byParagraphs` enumeration,
    /// so each returned wrapper contains exactly one paragraph (including any attached
    /// newline or paragraph‐separator attributes).
    func paragraphs() -> [KishoRichText] {
        let full = self.attributedString
        let fullNSString = full.string as NSString
        var result: [KishoRichText] = []

        // Enumerate by paragraph: this yields each “paragraph substring” and its range.
        fullNSString.enumerateSubstrings(
            in: NSRange(location: 0, length: fullNSString.length),
            options: .byParagraphs
        ) { (substring, substringRange, enclosingRange, stop) in
            // substringRange is the character range of this paragraph (without trailing newline),
            // but we want the full attributed substring including any paragraph separator.
            // So use 'enclosingRange' to include the final newline (if any).
            let paragraphRange = enclosingRange

            // Extract the attributed substring for this paragraph
            let subAttrString = full.attributedSubstring(from: paragraphRange)

            // Wrap it in a new KishoRichText
            let newRich = KishoRichText()
            newRich.attributedString = subAttrString
            result.append(newRich)
        }

        return result
    }
    

        /// A reasonable “default title” drawn from the first short sentence (≤ 20 words) of the content.
        /// - If the attributed string is empty (after trimming whitespace/newlines), returns "Untitled".
        /// - Otherwise, enumerates by sentences; if it finds a sentence with ≤ 20 words, returns that.
        /// - If no sentence under 20 words is found, returns the first 20 words of the text joined by spaces.
        var defaultTitle: String {
            // 1) Get the plain string and trim whitespace/newlines
            let fullString = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fullString.isEmpty else {
                return "Untitled"
            }

            // 2) Try to find a “short” (≤ 20‐word) sentence
            let nsString = fullString as NSString
            var shortSentence: String? = nil

            nsString.enumerateSubstrings(
                in: NSRange(location: 0, length: nsString.length),
                options: .bySentences
            ) { (substring, substringRange, enclosingRange, stop) in
                guard
                    let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !sentence.isEmpty
                else { return }

                let wordCount = sentence
                    .split { $0.isWhitespace }
                    .count
                if wordCount <= 20 {
                    shortSentence = sentence
                    stop.pointee = true
                }
            }

            if let title = shortSentence {
                return title
            }

            // 3) No sentence under 20 words found → return first 20 words
            let allWords = fullString
                .split { $0.isWhitespace }
            let firstWords = allWords.prefix(20)
            return firstWords.joined(separator: " ")
        }


        /// Returns a new KishoRichText which is the concatenation of `parts`,
        /// with a single newline inserted between each part’s attributed string.
        static func joined(_ parts: [KishoRichText]) -> KishoRichText {
            let result = KishoRichText()
            let combined = NSMutableAttributedString()

            for (index, part) in parts.enumerated() {
                // Append this part’s attributedString
                combined.append(part.attributedString)

                // If not the last element, append one newline (preserving default attributes)
                if index < parts.count - 1 {
                    combined.append(NSAttributedString(string: "\n"))
                }
            }

            // Assign back to the wrapper’s published property
            result.attributedString = combined
            return result
        }
    
}

/// Convenience extension to export NSAttributedString as RTF data.
extension NSAttributedString {
    /// Returns RTF data for the entire string. If encoding fails, returns empty Data.
    func rtfData() -> Data {
        return (try? self.data(
            from: NSRange(location: 0, length: self.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
        )) ?? Data()
    }
}

/*
class KishoRichText: ObservableObject, Codable {
    
    @Published var attributedString: NSAttributedString
    
    init(rtfData: Data = Data()) {
        self.attributedString = (try? NSAttributedString(data: rtfData,
                                                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                        documentAttributes: nil)) ?? NSAttributedString(string: "")
        // … Codable conformance that encodes/decodes `attributedString.rtfData()` …
    }
}
// RTF helpers
extension NSAttributedString {
    func rtfData() -> Data {
        (try? self.data(from: NSRange(location: 0, length: length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    static func fromRTF(data: Data) -> NSAttributedString? {
        try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    }
}
*/

