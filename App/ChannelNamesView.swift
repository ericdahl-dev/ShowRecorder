import Recording
import SwiftUI

/// Every USB Channel in one list, to name them all at once before or during a Show. A name behaves as if typed
/// on the meter: shown at once, put on the files when the Take ends, kept in the Show. Clearing a row takes the
/// typed name off again.
struct ChannelNamesView: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Int: String] = [:]
    @State private var copyMessage: String?
    @FocusState private var focused: Int?

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
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
                            if !(drafts[row.number] ?? "").isEmpty {
                                Button { drafts[row.number] = nil; commit(row.number) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Clear the name for USB Channel \(row.number)")
                            }
                        }
                        if focused == row.number { chips(for: row) }
                    }
                }
                Section {
                    Button("Copy from last Show") { copyFromLastShow() }
                    if let copyMessage { Text(copyMessage).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
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
        .onAppear {
            drafts = model.recorder.channelNames
            // `-channelNames` opens the page for screenshots, with a row ready to show its chips.
            if launchFlag("-channelNames") { focused = 3 }
        }
        .onDisappear { commitAll() }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 440)
        #endif
    }

    /// Shortcut chips for the row being edited. Tapping one fills the name; free text stays possible.
    private func chips(for row: ChannelNameRow) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChannelNameShortcut.all, id: \.self) { shortcut in
                    Button(shortcut.title) {
                        let others = drafts.filter { $0.key != row.number }.map(\.value)
                        drafts[row.number] = shortcut.name(taken: others)
                        commit(row.number)
                        focused = row.number
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                // Names typed before, on this device.
                ForEach(model.recorder.savedChannelNames, id: \.self) { saved in
                    Button(saved) {
                        drafts[row.number] = saved
                        commit(row.number)
                        focused = row.number
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.secondary)
                }
            }
        }
    }

    private func copyFromLastShow() {
        if let count = model.recorder.copyChannelNamesFromLastShow() {
            drafts = model.recorder.channelNames
            copyMessage = count == 1 ? "Copied 1 name." : "Copied \(count) names."
        } else {
            copyMessage = model.recorder.currentShow == nil
                ? "There is no Show yet. Press record or start a Show first."
                : "The Show before this one has no names to copy."
        }
    }

    private var rows: [ChannelNameRow] {
        let sources = model.mixerLink.sources
        let mixerNames = Dictionary(uniqueKeysWithValues: sources.indices.filter { sources[$0].hasMixerName }.map { ($0, sources[$0].name) })
        return ChannelNameList.rows(channelCount: model.meterModel.channelCount, mixerNames: mixerNames, typed: drafts)
    }

    private func binding(for row: ChannelNameRow) -> Binding<String> {
        Binding(get: { drafts[row.number] ?? "" }, set: { text in
            drafts[row.number] = text
            // Emptying a row takes the name off right away, not only on Return or Done.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { commit(row.number) }
        })
    }

    private func commit(_ number: Int) {
        let text = (drafts[number] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { drafts[number] = nil }
        if model.recorder.channelNames[number] != (text.isEmpty ? nil : text) {
            model.recorder.updateChannelName(text, forChannel: number)
        }
    }

    private func commitAll() {
        for number in 1...max(model.meterModel.channelCount, 1) { commit(number) }
    }
}
