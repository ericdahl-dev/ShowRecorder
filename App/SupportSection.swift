import MixerLink
import Recording
import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif
#if os(macOS)
import AppKit
#endif

/// "Contact support" at the bottom of Settings (#722): opens an email to support in Mail with the app and device
/// details filled in, for the user to read, edit and send. Free and Pro alike.
struct SupportSection: View {
    var model: RecordScreenModel
    @Environment(\.openURL) private var openURL
    /// The newest Show report on the Device, found when the section appears; nil when there's none.
    @State private var report: URL?
    @State private var attachReport = false
    #if canImport(MessageUI)
    @State private var composing = false
    #endif

    var body: some View {
        Section {
            Button("Contact support…") { contact() }
            // Only where the report can really go along: Mail's own composer. A mailto link can't carry a file.
            if let report, canAttach {
                Toggle("Attach the last Show report (\(report.deletingLastPathComponent().lastPathComponent))", isOn: $attachReport)
            }
        } footer: {
            Text("Opens an email to \(SupportMail.address) with the app version, this \(Self.hardwareWord), the audio interface and the Mixer Link filled in. You see all of it before you send, and nothing is sent unless you do.")
        }
        .task {
            let device = Recorder.defaultDeviceFolder
            report = await Task.detached { SupportMail.lastReport(showFolders: ShowList.read(device: device, drive: nil).map(\.folder)) }.value
        }
        #if canImport(MessageUI)
        .sheet(isPresented: $composing) {
            MailComposer(body: SupportMail.body(details), attachment: attachReport ? report : nil)
                .ignoresSafeArea()
        }
        #endif
    }

    private var details: SupportMail.Details {
        let family: String? = switch model.armedFamily {
        case .xAir: "X Air"
        case .x32: "X32"
        case nil: nil
        }
        var mixerLink: String?
        if case .up(let identity, _) = model.mixer.status ?? .idle {
            mixerLink = [family, "\(identity.model), firmware \(identity.firmware)"].compactMap { $0 }.joined(separator: " · ")
        }
        return SupportMail.Details(
            version: AppVersion.current, device: Self.hardwareModel, system: Self.systemVersion,
            armedInput: model.recorder.isArmed ? "\(model.compactInputSummary) · \(model.usbChannelSummary)" : nil,
            mixerLink: mixerLink)
    }

    private var canAttach: Bool {
        #if canImport(MessageUI)
        MFMailComposeViewController.canSendMail()
        #else
        NSSharingService(named: .composeEmail) != nil
        #endif
    }

    private func contact() {
        let body = SupportMail.body(details)
        #if canImport(MessageUI)
        if MFMailComposeViewController.canSendMail() { composing = true; return }
        #else
        if let mail = NSSharingService(named: .composeEmail) {
            mail.recipients = [SupportMail.address]
            mail.subject = SupportMail.subject
            let items: [Any] = [body] + (attachReport ? [report].compactMap { $0 } : [])
            if mail.canPerform(withItems: items) { mail.perform(withItems: items); return }
        }
        #endif
        if let url = SupportMail.mailtoURL(body: body) { openURL(url) }
    }

    #if os(macOS)
    private static let hardwareWord = "Mac"
    #else
    private static let hardwareWord = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    #endif

    /// "iPhone16,1" or "Mac15,3": the exact model, which "iPhone" alone doesn't say.
    private static var hardwareModel: String {
        #if os(macOS)
        let key = "hw.model"
        #else
        let key = "hw.machine"
        #endif
        var size = 0
        sysctlbyname(key, nil, &size, nil, 0)
        var bytes = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname(key, &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let name = "macOS"
        #else
        let name = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
        return "\(name) \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

#if canImport(MessageUI)
/// Mail's own composer, filled in with the support address, subject and body, and the Show report when chosen.
private struct MailComposer: UIViewControllerRepresentable {
    let body: String
    let attachment: URL?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([SupportMail.address])
        mail.setSubject(SupportMail.subject)
        mail.setMessageBody(body, isHTML: false)
        if let attachment, let data = try? Data(contentsOf: attachment) {
            mail.addAttachmentData(data, mimeType: "text/html", fileName: attachment.lastPathComponent)
        }
        return mail
    }

    func updateUIViewController(_ mail: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    /// Mail calls its delegate on the main thread.
    @MainActor final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}
#endif
