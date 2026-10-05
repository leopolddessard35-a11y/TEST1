import SwiftUI

/// Étape 2 du projet : journal alimentaire avec scan de code-barres (Open Food Facts + table Ciqual).
struct NutritionView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { profile, snapshot in
                    VStack(spacing: 16) {
                        if let phase = snapshot.plan.currentWeek?.phase {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionTitle(title: "Objectif du moment", symbol: "target")
                                    Text(phase.nutritionFocus).font(.subheadline)
                                    if profile.weightKg > 0 {
                                        Text("Protéines : \((profile.weightKg * 1.8).noDecimal)–\((profile.weightKg * 2.2).noDecimal) g par jour")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                        }
                        EmptyStateCard(
                            title: "Journal alimentaire : prochaine étape",
                            message: "Scan du code-barres, calcul automatique des calories, protéines, glucides et lipides au gramme près, repas favoris. Le module arrive dans la prochaine version.",
                            symbol: "barcode.viewfinder")
                    }
                    .padding(.horizontal, 16)
                }
            }
            .background(AppBackground())
            .navigationTitle("Nutrition")
        }
    }
}
