//
//  KishoDocumentView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct KishoDocumentView: View {
  //  @Binding var document: KishoDocumentModel
   
    @State private var showDeleteAlert = false
    @StateObject private var find = FindState()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @AppStorage(KishoPreferences.Key.hasShownWelcome) private var hasShownWelcome = false
    @AppStorage(KishoPreferences.Key.showInspector) private var showInspector = false
    @AppStorage(KishoPreferences.Key.editorTheme) private var editorThemeRaw = EditorTheme.system.rawValue
    /// Focus Mode is per window: just the cards, the current block bright.
    @State private var focusMode = false
    @State private var columns: NavigationSplitViewVisibility = .all

    private var editorTheme: EditorTheme { EditorTheme(rawValue: editorThemeRaw) ?? .system }

    @EnvironmentObject var document : KishoDocumentModel

    

    
    let fileURL : URL?
    
    /// A computed “title” that tracks the file’s name if available,
      /// otherwise falls back to your model’s internal title (or “Untitled”).
    private var documentTitle: String {
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return  "Untitled"
       
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            
            KishoSidebarOutlineView(showDeleteAlert: $showDeleteAlert)
                .environmentObject(self.document)
                .environmentObject(find)
                .focusedValue(\.kishoFindState, find)
                .focusedValue(\.kishoDocumentModel, document)
                .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                .focusedValue(\.showDeleteAlert , $showDeleteAlert)
                .focusedValue(\.kishoFocusMode, $focusMode)
                .frame(minWidth: 220)
    
        } detail: {
            HStack(spacing: 0) {
                KishoCardListEditorView()
                    .environmentObject(self.document)
                    .environmentObject(find)
                    .focusedValue(\.kishoFindState, find)
                    .focusedValue(\.kishoDocumentModel, document)
                    .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                    .focusedValue(\.showDeleteAlert , $showDeleteAlert)
                    .focusedValue(\.kishoFocusMode, $focusMode)
                if showInspector && !focusMode {
                    Divider()
                    BlockInspectorView()
                        .environmentObject(self.document)
                        .focusedValue(\.kishoDocumentModel, document)
                        .focusedValue(\.selectedSectionID , $document.selectedSectionID)
                        .focusedValue(\.kishoFocusMode, $focusMode)
                }
            }
            .environment(\.kishoFocusMode, focusMode)
            .environment(\.kishoEditorTheme, editorTheme)
        }
        .focusedSceneObject(document)
        .onChange(of: focusMode) { on in
            // Quick rather than animated: the sidebar, toolbar items and card
            // width all change at once and animating them together looks messy.
            withAnimation(.easeOut(duration: 0.12)) { columns = on ? .detailOnly : .all }
        }
        .toolbar {
            ToolbarItemGroup {
              // Focus mode keeps the toolbar (and so the window tabs) but
              // strips it down to the one way out.
              if focusMode {
                Button {
                    focusMode = false
                } label: {
                    Label("Exit Focus Mode", systemImage: "rectangle.inset.filled")
                }
                .help("Exit Focus Mode (⌥⌘F)")
              } else {
                ToolbarTypographyControlsView()
          
                Button {
                    document.makeChildren(undoManager: undoManager)
                } label: {
                    Label("Split", systemImage: "square.fill.text.grid.1x2")
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(document.selectedSection == nil)
                .help("Split the selected block's paragraphs into sub-blocks (⌥⌘P)")
                
                Button {
                    document.gather(undoManager: undoManager)
                } label: {
                    Label("Gather", systemImage: "rectangle.compress.vertical")
                }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(document.selectedSection?.children.isEmpty ?? true)
                .help("Gather all sub-block text back into the selected block (⌥⌘G)")
                
                Button {
                    find.show()
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .help("Find and replace across all blocks (⌘F)")

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(showInspector ? "Hide the block inspector (⌥⌘I)" : "Show the block inspector: status, colour, synopsis, notes (⌥⌘I)")

                // Share the .kisho file itself (Mail, AirDrop, Messages…).
                // Exports to other formats live under File ▸ Export As.
                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Share this document file")
                } else {
                    Button {
                        NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Save the document first to share it")
                }
         
                Button {
                    undoManager?.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.left")
                }
                .disabled(!(undoManager?.canUndo ?? false))
                .help("Undo")
                 
                Button {
                    undoManager?.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.right")
                }
                .disabled(!(undoManager?.canRedo ?? false))
                .help("Redo")
           
                Button {
                    document.addSiblingSection(using: undoManager)
                } label: {
                    Label("Add Sibling", systemImage: "plus")
                }
                .keyboardShortcut("=", modifiers: [.command])
                .help("Add a block after the selected one, at the same level (⌘=)")

                Button {
                    document.addChildSection(using: undoManager)
                } label: {
                    Label("Add Child", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])
                .disabled(document.selectedSection == nil)
                .help("Add a sub-block inside the selected block (⇧⌘=)")

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Block", systemImage: "trash")
                }
                .disabled(document.selectedSection == nil)
                .help("Delete the selected block and its sub-blocks (⇧⌘⌫)")
              }
            }
        }
        .background(WindowDocumentRegistrar(model: document))
        .onAppear {
            // First launch: open the one-page guide beside the document.
            guard !hasShownWelcome else { return }
            hasShownWelcome = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                openWindow(id: KishoHelpView.windowID)
            }
        }
        .alert("Delete Block?",
               isPresented: $showDeleteAlert,
               actions: {
            Button("Delete") {
             
                document.deleteSelectedSection(using: undoManager)
                }
            .keyboardShortcut(.defaultAction)
            
            
            Button("Cancel", role: .cancel) { }
        },
               message: {
            Text("Are you sure you want to delete the selected block? Its sub-blocks will be deleted with it.")
        }
        )
        
    }

 

}
