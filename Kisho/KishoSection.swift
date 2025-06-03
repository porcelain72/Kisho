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
    @Published var richTextData: Data       // RTF‐encoded text
    @Published var children: [KishoSection] // nested sections
    
    // NOTE: We do not store `parent` in the file; we rebuild it after decoding
    weak var parent: KishoSection?
    
    let id: UUID
    let createdAt: Date
    @Published var modifiedAt: Date

    // MARK: - CodingKeys for Codable
    enum CodingKeys: String, CodingKey {
        case id, title, richTextData, children, createdAt, modifiedAt
    }
    
    // MARK: - Initializers
    init(
        id: UUID = UUID(),
        title: String,
        richTextData: Data = NSAttributedString(string: "").rtfData(),
        children: [KishoSection] = [],
        parent: KishoSection? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.richTextData = richTextData
        self.children = children
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
        richTextData = try container.decode(Data.self,  forKey: .richTextData)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        
        // First decode children as an array of KishoSection
        let decodedChildren = try container.decode([KishoSection].self, forKey: .children)
        
        // Now set published children and re‐establish parent links
        children = decodedChildren
        for child in children {
            child.parent = self
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id,       forKey: .id)
        try container.encode(title,    forKey: .title)
        try container.encode(richTextData, forKey: .richTextData)
        try container.encode(createdAt,   forKey: .createdAt)
        try container.encode(modifiedAt,  forKey: .modifiedAt)
        try container.encode(children,  forKey: .children)
    }
    
    // MARK: - Helpers for Rich Text
    var attributedText: NSAttributedString {
        get { NSAttributedString.fromRTF(data: richTextData) ?? .init(string: "") }
        set { richTextData = newValue.rtfData() }
    }
}




