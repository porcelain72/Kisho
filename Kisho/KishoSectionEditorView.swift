//
//  KishoSectionEditorView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

import SwiftUI
import RichTextEditor

#if os(macOS)

struct KishoSectionEditorView: View {
    @EnvironmentObject var document : KishoDocumentModel
    
    @ObservedObject var section: KishoSection
    
    @Binding var focusTitle: Bool
    @State private var tagInput: String = ""
    
    // ← FocusState for the title field
    @FocusState private var isTitleFocused: Bool
    // ← FocusState for the rich‐text editor
    @FocusState private var isRichTextFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20.0) {
            TextField("Section Title", text: $section.title)
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .modifier(CellModifier(depth:self.document.depth(forSection: section), selected: true	))
            
            ZStack{
                Color.white
                VStack{
                    
                    RichTextEditor(attributedText: $section.content.attributedString, inspector: $section.inspectorVersion)
                    
                        .frame(minHeight: 200)
                        .focused($isRichTextFocused)
                    Rectangle()
                        .foregroundStyle(Color.white)
                        .frame(height: 100)
                }
                .padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 25.0))
            
            // ─── Tags Field ───
            TagEditorView(
                tags: $section.tags,
                allAvailableTags: document.allTags
            )

        }
        
        .padding()
        .onAppear {
            if focusTitle {
                // → Delay slightly so SplitView finishes handing off focus to content pane
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTitleFocused = true
                    // Reset the flag so we don’t refocus repeatedly
                    focusTitle = false
                }
            } else {
                // No “focusTitle” request means user clicked an existing section.
                // Focus the rich‐text editor instead:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isRichTextFocused = true
                }
            }
            
        }
        .onChange(of: section.id) { _ in
            if focusTitle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTitleFocused = true
                    focusTitle = false
                }
            }  else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isRichTextFocused = true
                }
            }
        }
        .id(section.id)
        
        
    }
    
    private func commitTags() {
        let cleaned = tagInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        section.tags = cleaned
    }
    
}
#endif
