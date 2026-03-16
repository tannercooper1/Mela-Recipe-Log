import Foundation
import Combine
import SwiftUI

class RecipeStore: ObservableObject {
    @Published var recipes: [Recipe] = []
    @Published var syncMessage: String? = nil
    @Published var lastSyncDate: Date? = nil

    private let fileName = "KitchenLog.json"
    private var fileURL: URL? { iCloudFileURL ?? localFileURL }
    private var metadataQuery: NSMetadataQuery?
    private var saveDebounceTask: Task<Void, Never>? = nil

    // MARK: - File URLs

    private var iCloudFileURL: URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent(fileName)
    }

    private var localFileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    // MARK: - Init

    init() {
        ensureDocumentsDirectory()
        load()
        startICloudObserver()
    }

    private func ensureDocumentsDirectory() {
        guard let iCloudURL = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") else { return }
        if !FileManager.default.fileExists(atPath: iCloudURL.path) {
            try? FileManager.default.createDirectory(at: iCloudURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Load & Save

    func load() {
        guard let url = fileURL else { return }
        if url == iCloudFileURL {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Recipe].self, from: data) else { return }
        DispatchQueue.main.async {
            self.recipes = decoded
            self.lastSyncDate = Date()
        }
    }

    func save() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self.writeToDisk()
        }
    }

    private func writeToDisk() async {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(recipes) else { return }
        do {
            try data.write(to: url, options: .atomic)
            await MainActor.run { self.lastSyncDate = Date() }
        } catch {
            await MainActor.run { self.syncMessage = "Save failed: \(error.localizedDescription)" }
        }
    }

    // MARK: - iCloud file observer

    private func startICloudObserver() {
        guard iCloudFileURL != nil else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidUpdate), name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidFinish), name: .NSMetadataQueryDidFinishGathering, object: query)
        query.start()
        self.metadataQuery = query
    }

    @objc private func metadataQueryDidFinish(_ notification: Notification) {
        metadataQuery?.disableUpdates(); load(); metadataQuery?.enableUpdates()
    }
    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        metadataQuery?.disableUpdates(); load(); metadataQuery?.enableUpdates()
    }

    // MARK: - Recipe mutations

    func addRecipe(_ recipe: Recipe) { recipes.append(recipe); save() }

    func deleteRecipe(_ recipe: Recipe) { recipes.removeAll { $0.id == recipe.id }; save() }

    func logCook(recipeID: UUID, entry: CookEntry) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipeID }) else { return }
        recipes[idx].cooks.append(entry); save()
    }

    func deleteCook(recipeID: UUID, entryID: UUID) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipeID }) else { return }
        recipes[idx].cooks.removeAll { $0.id == entryID }; save()
    }

    func updateRecipe(_ recipe: Recipe) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[idx] = recipe; save()
    }

    // MARK: - Mela import

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
                let isDuplicate = recipes.contains {
                    ($0.melaID != nil && $0.melaID == mela.id) ||
                    $0.name.lowercased() == mela.title.lowercased()
                }
                if isDuplicate { skipped += 1 } else { recipes.append(Recipe(from: mela)); imported += 1 }
            }
            if imported > 0 { save() }
            syncMessage = "\(imported) imported, \(skipped) already in log"
        }
        return (imported, skipped)
    }

    private func parseMelaRecipesZip(url: URL) throws -> [MelaRecipe] {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let data = try Data(contentsOf: url)
        let zipFile = tmpDir.appendingPathComponent("archive.zip")
        try data.write(to: zipFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipFile.path, "-d", tmpDir.path]
        try process.run()
        process.waitUntilExit()

        var melas: [MelaRecipe] = []
        let contents = (try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        for fileURL in contents {
            if fileURL.pathExtension.lowercased() == "melarecipe",
               let recipe = try? parseSingleMelaRecipe(url: fileURL) {
                melas.append(recipe)
            }
        }
        return melas
    }

    private func parseSingleMelaRecipe(url: URL) throws -> MelaRecipe? {
        let data = try Data(contentsOf: url)
        return try? JSONDecoder().decode(MelaRecipe.self, from: data)
    }

    // MARK: - Stats

    var stats: AppStats {
        let totalCooks = recipes.reduce(0) { $0 + $1.cooks.count }
        let allRatings = recipes.flatMap { $0.cooks.filter { $0.rating > 0 }.map(\.rating) }
        let avgRating: Double? = allRatings.isEmpty ? nil : Double(allRatings.reduce(0, +)) / Double(allRatings.count)
        let mostCooked = recipes.filter { !$0.cooks.isEmpty }.map { (recipe: $0, count: $0.cooks.count) }.sorted { $0.count > $1.count }.prefix(5).map { $0 }
        let recentCooks = recipes.flatMap { r in r.cooks.map { (recipe: r, entry: $0) } }.sorted { $0.entry.date > $1.entry.date }.prefix(10).map { $0 }
        return AppStats(totalRecipes: recipes.count, totalCooks: totalCooks, averageRating: avgRating, mostCooked: mostCooked, recentCooks: recentCooks)
    }
}
