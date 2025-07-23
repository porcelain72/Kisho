//
//  KishSidebarOutlineView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct KishoSidebarOutlineView: View {
    @EnvironmentObject var document : KishoDocumentModel
    @Binding var showDeleteAlert : Bool

    
    var body: some View {
        Group{
#if os(iOS)
            
            bodyIOS()
            
#else
            bodyMAC()
#endif
        }
    }
#if os(iOS)
    @ViewBuilder func bodyIOS() -> some View {
        
        List {
          //  VStack(alignment: .leading, spacing: 0) {
                ForEach(document.sections) { section in
                    SectionRow(section: section, depth: 0)
                   // Text(section.title)
                }
             
          //  }
        }
        .listStyle(.plain)
    }
#else
    @ViewBuilder func bodyMAC() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(document.sections) { section in
                    SectionRow(section: section, depth: 0)
                      
                }
             
            }
        }
    }
#endif

}


