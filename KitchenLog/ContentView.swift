import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RecipeStore

    var body: some View {
        TabView {
            RecipeListView()
                .tabItem {
                    Label("Recipes", systemImage: "fork.knife")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
        }
    }
}
