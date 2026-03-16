import Foundation
import SwiftUI

// MARK: - Mela file format models

struct MelaRecipe: Decodable {
    let id: String?
    let title: String
    let categories: [String]?
    let yield: String?
    let link: String?
    let ingredients: String?
    let instructions: String?
    let notes: String?
    let prepTime: String?
    let cookTime: String?
}

// MARK: - App models

struct CookEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var rating: Int  // 0–5
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), rating: Int = 0, note: String = "") {
        self.id = id
        self.date = date
        self.rating = rating
        self.note = note
    }
}

struct Recipe: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var melaID: String?       // original Mela identifier for deduplication
    var name: String
    var category: String
    var baseServings: Int
    var source: String
    var cooks: [CookEntry]

    var averageRating: Double? {
        let rated = cooks.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return nil }
        return Double(rated.map(\.rating).reduce(0, +)) / Double(rated.count)
    }

    var lastCooked: Date? {
        cooks.map(\.date).max()
    }

    init(from mela: MelaRecipe) {
        self.id = UUID()
        self.melaID = mela.id
        self.name = mela.title
        self.category = mela.categories?.first ?? ""
        self.baseServings = Int(mela.yield ?? "") ?? 4
        self.source = mela.link ?? ""
        self.cooks = []
    }

    init(id: UUID = UUID(), name: String, category: String = "", baseServings: Int = 4, source: String = "") {
        self.id = id
        self.name = name
        self.category = category
        self.baseServings = baseServings
        self.source = source
        self.cooks = []
    }
}

// MARK: - Stats

struct AppStats {
    let totalRecipes: Int
    let totalCooks: Int
    let averageRating: Double?
    let mostCooked: [(recipe: Recipe, count: Int)]
    let recentCooks: [(recipe: Recipe, entry: CookEntry)]
}
