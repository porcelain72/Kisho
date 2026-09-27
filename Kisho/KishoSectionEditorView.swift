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
    @Environment(\.undoManager) private var undoManager
    @ObservedObject var section: KishoSection

    @Binding var focusTitle: Bool
    @State private var tagInput: String = ""

    @StateObject private var subtreeEditor: SectionSubtreeEditorModel

    @FocusState private var isTitleFocused: Bool
    @FocusState private var isRichTextFocused: Bool

    init(section: KishoSection, focusTitle: Binding<Bool>) {
        self.section = section
        self._focusTitle = focusTitle
        self._subtreeEditor = StateObject(wrappedValue: SectionSubtreeEditorModel(section: section))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20.0) {
            TextField("Section Title", text: $section.title)
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .modifier(CellModifier(depth:self.document.depth(forSection: section), selected: true	))

            ZStack{
                Color(NSColor.textBackgroundColor)

                VStack{

                    RichTextEditor(
                        content: subtreeEditor.compositeContent,
                        inspector: $section.inspectorVersion,
                        undoManager: undoManager
                    )
                        .frame(minHeight: 200)
                        .focused($isRichTextFocused)
                    Rectangle()
                        .foregroundStyle(Color(NSColor.textBackgroundColor)
)
                        .frame(height: 100)
                }
                .padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 25.0))

            TagEditorView(
                tags: $section.tags,
                allAvailableTags: document.allTags
            )

        }

        .padding()
        .onAppear {
            subtreeEditor.undoManager = undoManager
            if focusTitle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTitleFocused = true
                    focusTitle = false
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isRichTextFocused = true
                }
            }

        }
        .onChange(of: section.id) { _ in
            subtreeEditor.updateRoot(section)
            subtreeEditor.undoManager = undoManager
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
