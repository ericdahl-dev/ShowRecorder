import Recording
import SwiftUI

/// Every USB Channel in one list, to name them all at once before or during a Show. A name behaves as if typed
/// on the meter: shown at once, put on the files when the Take ends, kept in the Show. Clearing a row takes the
/// typed name off again.
struct ChannelNamesView: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Int: String] = [:]
    @FocusState private var focused: Int?

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                HStack {
                    Text("\(row.number)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                    TextField(row.hint, text: binding(for: row))
                        .focused($focused, equals: row.number)
                        .submitLabel(.next)
                        .onSubmit { commit(row.number); focused = row.number < rows.count ? row.number + 1 : nil }
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Name for USB Channel \(row.number)")
                }
                }
                Section {} footer: {
                    Text("The files take the names when the Take ends. A name stays for the rest of the Show.")
                }
            }
            .navigationTitle("Channel names")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { commitAll(); dismiss() } }
            }
        }
        .onAppear { drafts = model.recorder.channelNames }
        .onDisappear { commitAll() }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 440)
        #endif
    }

    private var rows: [ChannelNameRow] {
        let sources = model.mixerLink.sources
        let mixerNames = Dictionary(uniqueKeysWithValues: sources.indices.filter { sources[$0].hasMixerName }.map { ($0, sources[$0].name) })
        return ChannelNameList.rows(channelCount: model.meters.count, mixerNames: mixerNames, typed: drafts)
    }

    private func binding(for row: ChannelNameRow) -> Binding<String> {
        Binding(get: { drafts[row.number] ?? "" }, set: { drafts[row.number] = $0 })
    }

    private func commit(_ number: Int) {
        let text = (drafts[number] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            drafts[number] = nil
            model.recorder.clearChannelName(forChannel: number)
        } else if model.recorder.channelNames[number] != text {
            model.recorder.setChannelName(text, forChannel: number)
        }
    }

    private func commitAll() {
        for number in 1...max(model.meters.count, 1) { commit(number) }
    }
}
