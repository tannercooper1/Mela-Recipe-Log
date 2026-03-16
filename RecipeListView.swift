import SwiftUI
import UniformTypeIdentifiers

struct RecipeListView: View {
    @EnvironmentObject var store: RecipeStore
    @State private var searchText = ""
    @State private var showingImporter = false
    @State private var showingAddRecipe = false
    @State private var importResult: String? = nil
    @State private var isImporting = false

    var filtered: [Recipe] {
        if searchText.isEmpty { return store.recipes.sorted { $0.name < $1.name } }
        return store.recipes
            .filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.recipes.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filtered) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                RecipeRowView(recipe: recipe)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                store.deleteRecipe(filtered[i])
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search recipes")
                }
            }
            .navigationTitle("Kitchen Log")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingAddRecipe = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    Menu {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import from Mela…", systemImage: "square.and.arrow.down")
                        }
                        if let msg = store.syncMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "melarecipes") ?? .data,
                    UTType(filenameExtension: "melarecipe") ?? .json,
                ],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .sheet(isPresented: $showingAddRecipe) {
                AddRecipeView()
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Import complete", isPresented: .constant(importResult != nil), actions: {
                Button("OK") { importResult = nil }
            }, message: {
                Text(importResult ?? "")
            })
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No recipes yet")
                .font(.title3)
                .fontWeight(.medium)
            Text("Import your Mela library or add a recipe manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Import from Mela") {
                showingImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func handleImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isImporting = true
        Task {
            do {
                let (imported, skipped) = try await store.importMelaFile(url: url)
                await MainActor.run {
                    isImporting = false
                    importResult = "\(imported) recipe\(imported == 1 ? "" : "s") imported, \(skipped) already in log."
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importResult = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct RecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name)
                .font(.body)
            HStack(spacing: 8) {
                if !recipe.category.isEmpty {
                    Text(recipe.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let avg = recipe.averageRating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", avg))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !recipe.cooks.isEmpty {
                    Text("\(recipe.cooks.count) cook\(recipe.cooks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
