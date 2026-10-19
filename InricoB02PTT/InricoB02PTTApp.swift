import SwiftUI

@main
struct InricoB02PTTApp: App {
    @StateObject private var session = DemoPTTSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onAppear {
                    session.start()
                }
        }
    }
}
