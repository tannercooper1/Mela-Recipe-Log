import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: RecipeStore

    var stats: AppStats { store.stats }

    var body: some View {
        NavigationStack {
            List {
                // Summary cards
                Section {
                    HStack(spacing: 12) {
                        StatCard(value: "\(stats.totalRecipes)", label: "Recipes")
                        StatCard(value: "\(stats.totalCooks)", label: "Total cooks")
                        if let avg = stats.averageRating {
                            StatCard(
                                value: String(format: "%.1f", avg),
                                label: "Avg rating",
                                icon: "star.fill",
                                iconColor: .yellow
                            )
                        } else {
                            StatCard(value: "—", label: "Avg rating")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                // Most cooked
                if !stats.mostCooked.isEmpty {
                    Section("Most cooked") {
                        ForEach(stats.mostCooked, id: \.recipe.id) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.recipe.name)
                                        .font(.body)
                                    if !item.recipe.category.isEmpty {
                                        Text(item.recipe.category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(item.count) cook\(item.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Recent cooks
                if !stats.recentCooks.isEmpty {
                    Section("Recent cooks") {
                        ForEach(stats.recentCooks, id: \.entry.id) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.recipe.name)
                                        .font(.body)
                                    Text(item.entry.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.entry.rating > 0 {
                                    StarRatingDisplay(rating: item.entry.rating, size: .caption2)
                                }
                            }
                        }
                    }
                }

                if stats.totalCooks == 0 {
                    Section {
                        ContentUnavailableView(
                            "No cooks logged yet",
                            systemImage: "chart.bar",
                            description: Text("Start logging cooks to see insights here.")
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Stats")
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    var icon: String? = nil
    var iconColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(iconColor)
                }
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}
