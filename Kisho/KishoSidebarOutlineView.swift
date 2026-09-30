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
            ForEach(document.sections) { section in
                SectionRow(section: section, depth: 0)
            }
        }
        .listStyle(.plain)
    }
#else
    @ViewBuilder func bodyMAC() -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(document.sections) { section in
                            SectionRow(section: section, depth: 0)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: document.selectedSectionID) { newID in
                    guard let newID else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newID)
                    }
                }
            }

            Divider()
            HStack {
                Text("\(document.totalWordCount.formatted()) words")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(document.orderedSections.count) blocks")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
#endif
}
