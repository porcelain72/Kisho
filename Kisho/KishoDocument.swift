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
    /// Markdown files, which open as a new (untitled) Kisho document.
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// The on-disk document. It is a reference document because the model is a
/// class: SwiftUI serialises reference documents from a `snapshot` taken on
/// the main thread, so a save can never race with edits to the live tree.
///
/// Note: as with any SwiftUI document, an edit only marks the document dirty
/// (and schedules an autosave) if it is registered with the undo manager —
/// which is why every model mutation takes a `UndoManager`.
final class KishoDocument: ReferenceFileDocument {
    typealias Snapshot = Data

    /// Markdown is readable but not writable, so opening a .md file imports
    /// it into a new untitled document rather than editing the file in place.
    static var readableContentTypes: [UTType] { [.kishoDoc, .markdownText] }
    static var writableContentTypes: [UTType] { [.kishoDoc] }

    let model: KishoDocumentModel

    init(model: KishoDocumentModel = KishoDocumentModel()) {
        self.model = model
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if configuration.contentType == .kishoDoc {
            self.model = try JSONDecoder().decode(KishoDocumentModel.self, from: data)
        } else {
            // Markdown (or any plain text): build blocks from the headings.
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let typography = TypographySettings()
            self.model = KishoDocumentModel(sections: Markdown.sections(from: text, typography: typography))
            self.model.typography = typography
        }
    }

    func snapshot(contentType: UTType) throws -> Data {
        try JSONEncoder().encode(model)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: snapshot)
    }
}
