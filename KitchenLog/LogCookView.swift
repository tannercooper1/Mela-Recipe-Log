import SwiftUI

struct LogCookView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) var dismiss

    let recipeID: UUID

    @State private var date: Date = Date()
    @State private var rating: Int = 0
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("When did you cook this?") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section("How did it go?") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rating")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        InteractiveStarRating(rating: $rating)
                    }
                    .padding(.vertical, 4)

                    TextField("Notes (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log cook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = CookEntry(date: date, rating: rating, note: note)
                        store.logCook(recipeID: recipeID, entry: entry)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct InteractiveStarRating: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(i <= rating ? Color.yellow : Color(.tertiaryLabel))
                    .onTapGesture {
                        if rating == i {
                            rating = 0  // tap same star to clear
                        } else {
                            rating = i
                        }
                    }
                    .animation(.snappy(duration: 0.15), value: rating)
            }
            if rating > 0 {
                Button {
                    rating = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .padding(.leading, 4)
            }
        }
    }
}
