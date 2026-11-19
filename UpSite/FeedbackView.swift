import SwiftUI
import MessageUI
import UIKit

struct FeedbackView: View {
    @EnvironmentObject private var store: SiteStore
    @Environment(\.openURL) private var openURL
    @State private var kind = 0
    @State private var subject = ""
    @State private var message = ""
    @State private var includeDevice = true
    @State private var includeSites = false
    @State private var showMail = false
    @State private var result: String?

    var body: some View {
        List {
            Section {
                Text(L.s("feedback.intro")).font(.subheadline).foregroundStyle(Theme.text2)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                Picker("", selection: $kind) {
                    Text(L.s("feedback.bug")).tag(0)
                    Text(L.s("feedback.idea")).tag(1)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.s("feedback.subject")).font(.caption).foregroundStyle(Theme.text3)
                    TextField(kind == 0 ? L.s("feedback.subject.bug") : L.s("feedback.subject.idea"), text: $subject)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind == 0 ? L.s("feedback.body.bug") : L.s("feedback.body.idea")).font(.caption).foregroundStyle(Theme.text3)
                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                }
            }
            .themedRows()

            Section {
                Toggle(isOn: $includeDevice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s("feedback.device"))
                        Text(deviceInfo).font(.footnote).foregroundStyle(Theme.text3)
                    }
                }
                Toggle(isOn: $includeSites) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s("feedback.sites"))
                        Text(L.s("feedback.sites.hint")).font(.footnote).foregroundStyle(Theme.text3)
                    }
                }
            }
            .themedRows()
            .tint(Theme.barUp)

            Section {
                Button(L.s("feedback.send")) { send() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text(L.s("feedback.footer", AppInfo.supportEmail)).frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .themedList()
        .navigationTitle(L.s("feedback.title"))
        .sheet(isPresented: $showMail) {
            MailView(to: AppInfo.supportEmail, subject: fullSubject, body: fullBody) { sent in
                if sent { result = L.s("feedback.thanks"); subject = ""; message = "" }
            }
            .ignoresSafeArea()
        }
        .alert(result ?? "", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button(L.s("action.ok"), role: .cancel) {}
        }
    }

    private var deviceInfo: String {
        "iOS \(UIDevice.current.systemVersion) · UpSite \(AppInfo.version) (\(AppInfo.build)) · \(UIDevice.current.model)"
    }

    private var fullSubject: String {
        let tag = kind == 0 ? L.s("feedback.bug") : L.s("feedback.idea")
        let s = subject.trimmingCharacters(in: .whitespaces)
        return "UpSite – \(tag)" + (s.isEmpty ? "" : ": \(s)")
    }

    private var fullBody: String {
        var b = message
        if includeDevice { b += "\n\n—\n\(deviceInfo)\n\(Locale.current.identifier) · \(TimeZone.current.identifier)" }
        if includeSites, !store.sites.isEmpty { b += "\n\n" + store.sites.map { "\($0.url) (\($0.status), \(CheckInterval.label($0.intervalMin)))" }.joined(separator: "\n") }
        return b
    }

    private func send() {
        if MFMailComposeViewController.canSendMail() {
            showMail = true
            return
        }
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = AppInfo.supportEmail
        c.queryItems = [URLQueryItem(name: "subject", value: fullSubject), URLQueryItem(name: "body", value: fullBody)]
        if let url = c.url { openURL(url) }
    }
}

struct MailView: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let body: String
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            done(result == .sent)
        }
    }
}
