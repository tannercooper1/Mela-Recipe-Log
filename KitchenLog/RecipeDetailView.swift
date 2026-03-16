import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject var store: RecipeStore
    let recipe: Recipe

    @State private var showingLogCook = false
    @State private var currentRecipe: Recipe

    init(recipe: Recipe) {
        self.recipe = recipe
        _currentRecipe = State(initialValue: recipe)
    }

    var body: some View {
        List {
            // Info section
            Section {
                if !currentRecipe.category.isEmpty {
                    LabeledContent("Category", value: currentRecipe.category)
                }
                if currentRecipe.baseServings > 0 {
                    LabeledContent("Base servings", value: "\(currentRecipe.baseServings)")
                }
                if !currentRecipe.source.isEmpty {
                    LabeledContent("Source", value: currentRecipe.source)
                }
            }

            // Cook history
            Section {
                if currentRecipe.cooks.isEmpty {
                    Text("No cooks logged yet")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(currentRecipe.cooks.sorted { $0.date > $1.date }) { entry in
                        CookEntryRow(entry: entry)
                    }
                    .onDelete { indexSet in
                        let sorted = currentRecipe.cooks.sorted { $0.date > $1.date }
                        for i in indexSet {
                            store.deleteCook(recipeID: currentRecipe.id, entryID: sorted[i].id)
                        }
                        syncRecipe()
                    }
                }
            } header: {
                Text("Cook history")
            }
        }
        .navigationTitle(currentRecipe.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLogCook = true
                } label: {
                    Label("Log cook", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingLogCook, onDismiss: syncRecipe) {
            LogCookView(recipeID: currentRecipe.id)
        }
        .onReceive(store.$recipes) { _ in
            syncRecipe()
        }
    }

    private func syncRecipe() {
        if let updated = store.recipes.first(where: { $0.id == recipe.id }) {
            currentRecipe = updated
        }
    }
}

struct CookEntryRow: View {
    let entry: CookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.rating > 0 {
                    StarRatingDisplay(rating: entry.rating)
                }
            }
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.body)
            }
        }
        .padding(.vertical, 2)
    }
}

struct StarRatingDisplay: View {
    let rating: Int
    var size: Font = .caption

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(size)
                    .foregroundStyle(i <= rating ? Color.yellow : Color(.tertiaryLabel))
            }
        }
    }
}
