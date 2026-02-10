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
        content: RichTextModel = RichTextModel(rtfData: NSAttributedString(string: "").rtfData()) ,
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
        content = try container.decode(RichTextModel.self,  forKey: .content)
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
    
    func joinedChildrenContent() -> RichTextModel {
        
        
      //  var childContent = KishoRichText.fromSections(self.children)
        var childContent = KishoSection.combinedRichText(from: self.children)
        return RichTextModel.joined([self.content, childContent])
    }
    
    
    // MARK: - Word Count
    
    /// Word count for this section's own content only.
    var wordCount: Int {
        let text = content.attributedString.string
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
    
    /// Aggregate word count: this section's content plus all descendants.
    var totalWordCount: Int {
        children.reduce(wordCount) { $0 + $1.totalWordCount }
    }
    
    func applyTypographyToSelfAndDescendants(font: NSFont, color: NSColor? = nil) {
        // Apply to this section
        self.content.applyTypography(font: font, color: color)
        
        // Recursively apply to children
        for child in children {
            child.applyTypographyToSelfAndDescendants(font: font, color: color)
        }
        
        // Trigger UI updates if needed
        self.inspectorVersion = UUID()
    }
    
}

extension KishoSection {
    static func combinedRichText(from sections: [KishoSection]) -> RichTextModel {
        let richParts = sections.map { $0.joinedChildrenContent() }
        return RichTextModel.joined(richParts)
    }
}







