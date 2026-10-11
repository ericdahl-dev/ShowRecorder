import Recording
import SwiftUI

/// The Show sheet: End Show first when a Show is open, then a name and venue to start another. Reached by tapping the Show line on the record screen.
struct NewShowSheet: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var venue = ""
    @State private var message: String?
    @State private var savingTemplate = false
    @State private var renaming: Template?
    @State private var templateName = ""

    private var sheet: ShowSheet {
        ShowSheet(openShowName: model.recorder.currentShow?.name, isRecording: model.recorder.isRecording)
    }

    var body: some View {
        NavigationStack {
            Form {
                if sheet.endShowFirst, let current = model.recorder.currentShow {
                    Section {
                        Text(current.name)
                        Button("End Show", role: .destructive) {
                            message = model.endShow()
                            if message == nil { dismiss() }
                        }
                        .disabled(!sheet.canEndShow)
                    } header: {
                        Text("Open Show")
                    } footer: {
                        Text(sheet.endShowNote)
                    }
                }
                templatesSection
                Section {
                    TextField("Name", text: $name)
                    TextField("Venue", text: $venue)
                } header: {
                    if sheet.endShowFirst { Text("Start another Show") }
                } footer: {
                    Text(sheet.startShowNote)
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle(sheet.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Show") {
                        message = model.startNewShow(name: name, venue: venue)
                        if message == nil { dismiss() }
                    }
                    .disabled(!sheet.canStartShow)
                }
            }
        }
        .alert("Save as Template", isPresented: $savingTemplate) {
            TextField("Template name", text: $templateName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.saveTemplate(named: templateName) }
        } message: {
            Text("Saves the channel names, Pre-roll and Mixer. The name is also the Show's name.")
        }
        .alert("Rename Template", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Template name", text: $templateName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if let renaming { model.templates.rename(renaming.id, to: templateName) } }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
    }

    /// Start a Show from a Template, or save this setup as one (#33).
    @ViewBuilder private var templatesSection: some View {
        let access = model.templateAccess
        Section {
            ForEach(model.templates.templates) { template in
                Button {
                    message = model.startShow(from: template)
                    if message == nil { dismiss() }
                } label: {
                    LabeledContent(template.name, value: template.venue ?? "")
                }
                .disabled(access != .usable)
                .swipeActions {
                    Button("Delete", role: .destructive) { model.templates.delete(template.id) }
                    Button("Rename") {
                        templateName = template.name
                        renaming = template
                    }
                }
                .contextMenu {
                    Button("Rename") {
                        templateName = template.name
                        renaming = template
                    }
                    Button("Delete", role: .destructive) { model.templates.delete(template.id) }
                }
            }
            Button("Save this setup as a Template…") {
                templateName = ""
                savingTemplate = true
            }
            .disabled(access == .proOnly)
        } header: {
            Text("Templates")
        } footer: {
            Text(access.note ?? "Starting from a Template ends the open Show and brings its channel names, Pre-roll and Mixer.")
        }
    }
}
