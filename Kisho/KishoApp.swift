//
//  KishoApp.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

import SwiftUI

@main
struct KishoApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: KishoDocument()) { file in
            KishoDocumentView(document: file.$document.model)
        }
    }
}
