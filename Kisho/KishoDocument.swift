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

    init(model: KishoDocumentModel = KishoDocumentModel()) {
        self.model = model
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
