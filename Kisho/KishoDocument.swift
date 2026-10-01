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
    /// Markdown files, for File ▸ Import Markdown….
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

    static var readableContentTypes: [UTType] { [.kishoDoc] }

    let model: KishoDocumentModel

    /// Content for the next new untitled document, set by File ▸ Import
    /// Markdown… immediately before asking AppKit for a new document. Going
    /// through the ordinary new-document path (rather than declaring Markdown
    /// as a readable type) is what makes Save behave: a document opened from
    /// a .md would otherwise keep that file as its URL and ⌘S would overwrite
    /// the Markdown with Kisho's JSON.
    static var pendingImport: KishoDocumentModel?

    init(model: KishoDocumentModel? = nil) {
        if let model {
            self.model = model
        } else if let pending = KishoDocument.pendingImport {
            KishoDocument.pendingImport = nil
            self.model = pending
        } else {
            self.model = KishoDocumentModel()
        }
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.model = try JSONDecoder().decode(KishoDocumentModel.self, from: data)
    }

    func snapshot(contentType: UTType) throws -> Data {
        try JSONEncoder().encode(model)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: snapshot)
    }
}
