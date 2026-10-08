import SwiftUI

/// Starts a Show on purpose, with a name and a venue. Reached by tapping the Show name on the record screen.
struct NewShowSheet: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var venue = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Venue", text: $venue)
                } footer: {
                    Text(footer)
                }
                if let current = model.recorder.currentShow {
                    Section("Open Show") {
                        Text(current.name)
                    }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New Show")
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
                    .disabled(model.recorder.isRecording)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
    }

    private var footer: String {
        model.recorder.isRecording
            ? "A Show can't be started during a Take."
            : "The Show ends the open one. The next Take is Take 01 of the new Show. Leave the name blank for \"Show\"."
    }
}
