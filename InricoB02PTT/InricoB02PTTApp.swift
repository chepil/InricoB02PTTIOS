import SwiftUI

@main
struct InricoB02PTTApp: App {
    @StateObject private var ble = B02PTTBleController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .onAppear {
                    ble.start()
                }
        }
    }
}
