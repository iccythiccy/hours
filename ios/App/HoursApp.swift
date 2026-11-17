import SwiftUI
import MessageUI

@main
struct HoursApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
                .onOpenURL { _ in model.refresh() }   // hours:// from the widgets
        }
    }
}

extension Color {
    static let hBg = Color(red: 0.043, green: 0.043, blue: 0.051)
    static let hCard = Color(red: 0.090, green: 0.090, blue: 0.102)
    static let hCard2 = Color(red: 0.122, green: 0.122, blue: 0.137)
    static let hLine = Color(red: 0.165, green: 0.165, blue: 0.184)
    static let hMuted = Color(red: 0.557, green: 0.557, blue: 0.588)
    static let hBlank = Color(red: 0.290, green: 0.290, blue: 0.322)
    static let hAccent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let hGreen = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let hOrange = Color(red: 1.0, green: 0.624, blue: 0.039)
    static let hRed = Color(red: 1.0, green: 0.541, blue: 0.502)
}

/// The Messages compose sheet. iPhone reports whether the text was actually sent.
struct MessageComposer: UIViewControllerRepresentable {
    let outgoing: Outgoing
    let onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = outgoing.recipients
        vc.body = outgoing.text
        vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void
        init(_ f: @escaping (MessageComposeResult) -> Void) { onFinish = f }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish(result)
        }
    }
}
