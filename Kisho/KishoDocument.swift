//
//  KishoDocument.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let kishoDoc = UTType(exportedAs: "com.pm.kisho.document")
    static let kishoSectionID = UTType(exportedAs: "com.pm.kisho.section-id")

}

struct KishoDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.kishoDoc] }

    var model: KishoDocumentModel

    init(model: KishoDocumentModel = KishoDocumentModel()) {
        self.model = model
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.model = try JSONDecoder().decode(KishoDocumentModel.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(model)
        return .init(regularFileWithContents: data)
    }
}


extension Binding where Value == [KishoSection] {
    /// Returns a binding to the `children` array for a section with the given ID.
    func childrenBinding(for id: UUID) -> Binding<[KishoSection]>? {
        for idx in wrappedValue.indices {
            if wrappedValue[idx].id == id {
                return self[idx].children
            }
            if let found = self[idx].children.childrenBinding(for: id) {
                return found
            }
        }
        return nil
    }
    
    /// Returns a binding to the parent array containing the section with the given ID.
    /// For root sections, just use the top-level binding.
    func parentBinding(for childID: UUID) -> Binding<[KishoSection]>? {
        for idx in wrappedValue.indices {
            let section = wrappedValue[idx]
            if section.children.contains(where: { $0.id == childID }) {
                return self[idx].children
            }
            if let found = self[idx].children.parentBinding(for: childID) {
                return found
            }
        }
        return nil
    }
    
    /// Returns a binding to the section with the given ID.
    func binding(for id: UUID) -> Binding<KishoSection>? {
        for idx in wrappedValue.indices {
            if wrappedValue[idx].id == id {
                return self[idx]
            }
            if let found = self[idx].children.binding(for: id) {
                return found
            }
        }
        return nil
    }
}
