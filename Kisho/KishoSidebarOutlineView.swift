//
//  KishSidebarOutlineView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct KishoSidebarOutlineView: View {
    @Binding var sections: [KishoSection]
    @Binding var selectedSectionID: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    SectionRow(
                        section: section,
                        selectedSectionID: $selectedSectionID,
                        allSections: $sections,        // <--- always the ROOT array
                        parentSections: $sections      // top-level: root is also the parent
                    )
                }
            }
        }
    }
}


