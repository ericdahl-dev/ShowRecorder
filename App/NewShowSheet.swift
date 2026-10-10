import Recording
import SwiftUI

/// The Show sheet: End Show first when a Show is open, then a name and venue to start another. Reached by tapping the Show line on the record screen.
struct NewShowSheet: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var venue = ""
    @State private var message: String?

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
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
    }
}
