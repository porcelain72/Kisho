//
//  KishoSectionEditorView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

import SwiftUI
import RichTextEditor


struct KishoSectionEditorView: View {
    @EnvironmentObject var document : KishoDocumentModel

    @ObservedObject var section: KishoSection
 //   @Binding var focusTitle: Bool

    // ← FocusState for the title field
     @FocusState private var isTitleFocused: Bool
     // ← FocusState for the rich‐text editor
    @FocusState private var isRichTextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20.0) {
            TextField("Section Title", text: $section.title)
                .textFieldStyle(.plain)
              //  .focused($isTitleFocused)
                .modifier(CellModifier(depth:self.document.depth(forSection: section), selected: true    ))
            
            ZStack{
                Color.white
                VStack{
                    /*
                    TextEditor(text: Binding(get: {
                        section.attributedText.string
                    }, set: { new in
                        section.attributedText = NSAttributedString(string: new)
                    }))
                    .focused($isRichTextFocused)
                    */
                    
                    RichTextEditor(attributedText: $section.content.attributedString, inspector: $section.inspectorVersion)
                     
                    .frame(minHeight: 200)
                //    .focused($isRichTextFocused)
                    Rectangle()
                        .foregroundStyle(Color.white)
                        .frame(height: 100)
                }
                .padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 25.0))
        }
        
        .padding()
        /*
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
         */
        .id(section.id)

        
    }
}
/*
import AppKit

public struct RichTextEditor: NSViewRepresentable {
    @Binding public var attributedText: NSAttributedString
    public var minimumBottomPadding: CGFloat = 40

    public init(attributedText: Binding<NSAttributedString>, minimumBottomPadding: CGFloat = 40) {
        self._attributedText = attributedText
        self.minimumBottomPadding = minimumBottomPadding
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textStorage?.setAttributedString(attributedText)
        textView.delegate = context.coordinator
        textView.postsFrameChangedNotifications = true
        textView.postsBoundsChangedNotifications = true
        textView.backgroundColor = .clear
        textView.textContainer?.widthTracksTextView = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewSelectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Only update if attributedText changed from outside (not from delegate)
        if !context.coordinator.ignoreNextUpdate {
            if textView.attributedString() != attributedText {
                context.coordinator.ignoreNextDelegate = true
                textView.textStorage?.setAttributedString(attributedText)
                context.coordinator.ignoreNextDelegate = false
            }
        } else {
            context.coordinator.ignoreNextUpdate = false
        }
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var ignoreNextDelegate = false
        var ignoreNextUpdate = false

        init(_ parent: RichTextEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if !ignoreNextDelegate {
                parent.attributedText = textView.attributedString()
                ignoreNextUpdate = true
                scrollCaretIfNeeded()
            }
        }

        @objc func textViewSelectionDidChange(_ notification: Notification) {
            scrollCaretIfNeeded()
        }

        func scrollCaretIfNeeded() {
            guard let textView = textView, let scrollView = scrollView else { return }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            let selectedRange = textView.selectedRange()
            guard selectedRange.location <= layoutManager.numberOfGlyphs else { return }

            let caretRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: selectedRange.location, length: 0),
                in: textContainer
            )

            let caretBottomInTextView = caretRect.maxY
            let textViewVisibleHeight = scrollView.contentView.bounds.height
            let textViewVisibleOriginY = scrollView.contentView.bounds.origin.y

            let caretBottomInVisible = caretBottomInTextView - textViewVisibleOriginY
            let shouldScroll = caretBottomInVisible > textViewVisibleHeight - parent.minimumBottomPadding

            if shouldScroll {
                let targetY = caretBottomInTextView - textViewVisibleHeight + parent.minimumBottomPadding
                let constrainedY = max(0, min(targetY, textView.bounds.height - textViewVisibleHeight))
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: constrainedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
}
*/

