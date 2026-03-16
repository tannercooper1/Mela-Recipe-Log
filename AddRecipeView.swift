import SwiftUI

struct AddRecipeView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var category = ""
    @State private var baseServings = 4
    @State private var source = ""

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Recipe name", text: $name)
                    TextField("Category (e.g. Pasta, Soup)", text: $category)
                }

                Section {
                    Stepper("Base servings: \(baseServings)", value: $baseServings, in: 1...50)
                    TextField("Source or URL (optional)", text: $source)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Add recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let recipe = Recipe(
                            name: name.trimmingCharacters(in: .whitespaces),
                            category: category.trimmingCharacters(in: .whitespaces),
                            baseServings: baseServings,
                            source: source.trimmingCharacters(in: .whitespaces)
                        )
                        store.addRecipe(recipe)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
