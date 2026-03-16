import Foundation
import Combine
import SwiftUI
import ZipArchive

class RecipeStore: ObservableObject {
    @Published var recipes: [Recipe] = []
    @Published var isLoading = false
    @Published var lastSyncDate: Date? = nil
    @Published var syncMessage: String? = nil

    private let iCloudStore = NSUbiquitousKeyValueStore.default
    private let localKey = "kitchenlog.recipes"
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore
        )
        iCloudStore.synchronize()
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(recipes) {
            iCloudStore.set(data, forKey: localKey)
            iCloudStore.synchronize()
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    func load() {
        // Prefer iCloud, fall back to local
        let data = iCloudStore.data(forKey: localKey)
            ?? UserDefaults.standard.data(forKey: localKey)
        if let data, let decoded = try? JSONDecoder().decode([Recipe].self, from: data) {
            recipes = decoded
        }
    }

    @objc private func iCloudDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.load()
        }
    }

    // MARK: - Recipe mutations

    func addRecipe(_ recipe: Recipe) {
        recipes.append(recipe)
        save()
    }

    func deleteRecipe(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        save()
    }

    func logCook(recipeID: UUID, entry: CookEntry) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipeID }) else { return }
        recipes[idx].cooks.append(entry)
        save()
    }

    func deleteCook(recipeID: UUID, entryID: UUID) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipeID }) else { return }
        recipes[idx].cooks.removeAll { $0.id == entryID }
        save()
    }

    func updateRecipe(_ recipe: Recipe) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[idx] = recipe
        save()
    }

    // MARK: - Mela import

    /// Import from a .melarecipes (zip) or .melarecipe (json) file URL
    /// Returns (imported, skipped) counts
    @discardableResult
    func importMelaFile(url: URL) async throws -> (imported: Int, skipped: Int) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        var melasToImport: [MelaRecipe] = []

        if ext == "melarecipes" || ext == "zip" {
            melasToImport = try parseMelaRecipesZip(url: url)
        } else if ext == "melarecipe" {
            if let recipe = try? parseSingleMelaRecipe(url: url) {
                melasToImport = [recipe]
            }
        }

        var imported = 0
        var skipped = 0

        await MainActor.run {
            for mela in melasToImport {
                let isDuplicate = recipes.contains(where: {
                    $0.melaID != nil && $0.melaID == mela.id ||
                    $0.name.lowercased() == mela.title.lowercased()
                })
                if isDuplicate {
                    skipped += 1
                } else {
                    recipes.append(Recipe(from: mela))
                    imported += 1
                }
            }
            if imported > 0 { save() }
            lastSyncDate = Date()
            syncMessage = "\(imported) imported, \(skipped) already in log"
        }

        return (imported, skipped)
    }

    private func parseMelaRecipesZip(url: URL) throws -> [MelaRecipe] {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Use system unzip since SSZipArchive may not be available
        let data = try Data(contentsOf: url)
        let zipFile = tmpDir.appendingPathComponent("archive.zip")
        try data.write(to: zipFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipFile.path, "-d", tmpDir.path]
        try process.run()
        process.waitUntilExit()

        var recipes: [MelaRecipe] = []
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []

        for fileURL in contents {
            if fileURL.pathExtension.lowercased() == "melarecipe" {
                if let recipe = try? parseSingleMelaRecipe(url: fileURL) {
                    recipes.append(recipe)
                }
            }
        }
        return recipes
    }

    private func parseSingleMelaRecipe(url: URL) throws -> MelaRecipe? {
        let data = try Data(contentsOf: url)
        return try? JSONDecoder().decode(MelaRecipe.self, from: data)
    }

    // MARK: - Stats

    var stats: AppStats {
        let totalCooks = recipes.reduce(0) { $0 + $1.cooks.count }
        let allRatings = recipes.flatMap { $0.cooks.filter { $0.rating > 0 }.map(\.rating) }
        let avgRating: Double? = allRatings.isEmpty ? nil :
            Double(allRatings.reduce(0, +)) / Double(allRatings.count)

        let mostCooked = recipes
            .filter { !$0.cooks.isEmpty }
            .map { (recipe: $0, count: $0.cooks.count) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }

        let recentCooks = recipes
            .flatMap { recipe in recipe.cooks.map { (recipe: recipe, entry: $0) } }
            .sorted { $0.entry.date > $1.entry.date }
            .prefix(10)
            .map { $0 }

        return AppStats(
            totalRecipes: recipes.count,
            totalCooks: totalCooks,
            averageRating: avgRating,
            mostCooked: mostCooked,
            recentCooks: recentCooks
        )
    }
}
