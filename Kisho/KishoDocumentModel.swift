//
//  KishoDocumentModel.swift
//  Kisho
//
//  Created by Peter Macdonald on 03/06/2025.
//

import SwiftUI

final class KishoDocumentModel: ObservableObject, Codable {
    @Published var sections: [KishoSection]
    
    enum CodingKeys: String, CodingKey { case sections }
    
    init(sections: [KishoSection] = [KishoSection(title: "Untitled Section")]) {
        self.sections = sections
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([KishoSection].self, forKey: .sections)
        self.sections = decoded
        // Fix parent pointers
        func fixParents(_ list: [KishoSection]) {
            for s in list {
                for child in s.children {
                    child.parent = s
                    fixParents([child])
                }
            }
        }
        fixParents(self.sections)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sections, forKey: .sections)
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
