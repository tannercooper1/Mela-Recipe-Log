import SwiftUI

@main
struct KitchenLogApp: App {
    @StateObject private var store = RecipeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
