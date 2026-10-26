import SwiftUI

#if os(iOS)
import MessageUI

private struct MailComposerView: UIViewControllerRepresentable {
    let draft: EmailDraft
    let onFinish: () -> Void

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true, completion: onFinish)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIViewController {
        guard MFMailComposeViewController.canSendMail() else {
            var components = URLComponents(string: "mailto:\(draft.recipient)")!
            components.queryItems = [URLQueryItem(name: "subject", value: draft.subject), URLQueryItem(name: "body", value: draft.body)]
            if let url = components.url { UIApplication.shared.open(url) }
            DispatchQueue.main.async(execute: onFinish)
            return UIViewController()
        }
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#endif

private struct EmailComposerModifier: ViewModifier {
    @Binding var draft: EmailDraft?

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(item: $draft) { value in
            MailComposerView(draft: value) { draft = nil }
        }
        #else
        content.onChange(of: draft?.id) { _, _ in
            guard let value = draft else { return }
            let service = NSSharingService(named: .composeEmail)
            service?.recipients = [value.recipient]
            service?.subject = value.subject
            service?.perform(withItems: [value.body])
            draft = nil
        }
        #endif
    }
}

extension View {
    func emailComposer(draft: Binding<EmailDraft?>) -> some View {
        modifier(EmailComposerModifier(draft: draft))
    }
}
