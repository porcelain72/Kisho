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

