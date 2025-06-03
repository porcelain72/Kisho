//
//  KishoInspectorView.swift
//  KishoMac
//
//  Created by Peter Macdonald on 20/05/2025.
//

import SwiftUI

/*
struct KishoInspectorView: View {
    @ObservedObject var section: KishoSection
    
    var body: some View {
        Form {
            Section("Tags") {
                // Replace with a real tag editor UI
                TextField("Add tag", text: .constant(""))
            }
            Section("Attachments") {
                // List attachments and add/remove buttons
                ForEach(section.attachments) { attachment in
                    HStack {
                        Image(systemName: iconName(for: attachment.type))
                        Text(attachment.fileName)
                        Spacer()
                        Button(role: .destructive) {
                            // Remove logic
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Button("Add Attachment") {
                    // Present file picker
                }
            }
            Section("Section Info") {
                Text("Created: \(section.createdAt, formatter: dateFormatter)")
                Text("Modified: \(section.modifiedAt, formatter: dateFormatter)")
            }
        }
        .padding()
        .frame(minWidth: 240)
    }
    
    func iconName(for type: KishoAttachmentType) -> String {
        switch type {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .audio: return "waveform"
        case .video: return "video"
        }
    }
}

private let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .short
    df.timeStyle = .short
    return df
}()
*/
