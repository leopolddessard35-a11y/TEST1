import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Ce qu'ouvre le bouton « + » de la barre d'onglets : toutes les saisies en un tap.
struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    var isSheet = false
    @State private var sheet: Entry?
    @State private var waterAdded: Double?
    @State private var importingHevy = false

    enum Entry: String, Identifiable {
        case food, workout, cardio, rpe, weight, symptom, life, unavailability, injury
        var id: String { rawValue }
    }

    private struct ActionGroup: Identifiable {
        var id: String { title }
        let title: String
        let actions: [Action]
    }

    private struct Action: Identifiable {
        let id: String
        let title: String
        let caption: String
        let symbol: String
        let tint: Color
        let entry: Entry
    }

    private let groups: [ActionGroup] = [
        ActionGroup(title: "Nutrition", actions: [
            Action(id: "food", title: "Repas", caption: "scan, favoris, récents", symbol: "fork.knife", tint: Theme.nutrition, entry: .food),
            Action(id: "weight", title: "Pesée", caption: "poids du matin", symbol: "scalemass.fill", tint: Theme.nutrition, entry: .weight)
        ]),
        ActionGroup(title: "Entraînement", actions: [
            Action(id: "workout", title: "Séance de muscu", caption: "séries, charges, repos", symbol: "dumbbell.fill", tint: Theme.strain, entry: .workout),
            Action(id: "cardio", title: "Séance d'endurance", caption: "vélo, course sans montre", symbol: "bicycle", tint: Theme.strain, entry: .cardio),
            Action(id: "rpe", title: "Effort ressenti", caption: "noter une séance", symbol: "gauge.with.dots.needle.67percent", tint: Theme.strain, entry: .rpe)
        ]),
        ActionGroup(title: "Corps et santé", actions: [
            Action(id: "symptom", title: "Symptôme", caption: "douleur, gêne", symbol: "bandage.fill", tint: Theme.warning, entry: .symptom),
            Action(id: "injury", title: "Blessure", caption: "adapte le plan", symbol: "cross.case.fill", tint: Theme.warning, entry: .injury)
        ]),
        ActionGroup(title: "Quotidien", actions: [
            Action(id: "life", title: "Hors sport", caption: "travaux, debout", symbol: "hammer.fill", tint: Theme.sleep, entry: .life),
            Action(id: "unavailability", title: "Imprévu", caption: "maladie, voyage…", symbol: "calendar.badge.exclamationmark", tint: Theme.sleep, entry: .unavailability)
        ])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if WorkoutDraft.load()?.exercises.isEmpty == false {
                        Button { sheet = .workout } label: {
                            Label("Reprendre la séance en cours", systemImage: "play.circle.fill")
                                .font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.strain)
                        .controlSize(.large)
                    }
                    waterCard
                    ForEach(groups) { group in
                        SectionHeader(title: group.title)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(group.actions) { action in
                                Button { sheet = action.entry } label: { tile(action) }
                                    .buttonStyle(.plain)
                            }
                            if group.title == "Entraînement" {
                                Button { importingHevy = true } label: {
                                    tile(Action(id: "hevy", title: "Import Hevy", caption: "fichier CSV exporté", symbol: "square.and.arrow.down.fill",
                                                tint: Theme.strain, entry: .workout))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Ajouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                }
            }
            .fileImporter(isPresented: $importingHevy, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                if case .success(let url) = result {
                    app.importHevy(from: url, context: context)
                }
            }
            .sheet(item: $sheet) { entry in
                switch entry {
                case .food: AddFoodView { app.dataVersion += 1 }
                case .workout: WorkoutLoggerView()
                case .cardio: CardioEntryForm()
                case .weight: WeightEntryForm()
                case .rpe: RPESheet()
                case .symptom: SymptomForm()
                case .life: LifeActivityForm()
                case .unavailability: UnavailabilityForm()
                case .injury: InjuryForm()
                }
            }
        }
    }

    private func tile(_ action: Action) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: action.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(action.tint.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(.subheadline.weight(.semibold))
                Text(action.caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 22)
    }

    private var waterCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Eau", systemImage: "drop.fill").font(.headline).foregroundStyle(Theme.sleep)
                    Spacer()
                    if let waterAdded {
                        Text("+\(Int(waterAdded)) ml ajoutés").font(.caption.weight(.semibold)).foregroundStyle(Theme.recovery)
                            .transition(.opacity)
                    }
                }
                HStack(spacing: 8) {
                    ForEach([250.0, 500, 750], id: \.self) { ml in
                        Button("+\(Int(ml)) ml") {
                            QuickActions.addWater(ml, context: context)
                            app.dataVersion += 1
                            withAnimation { waterAdded = (waterAdded ?? 0) + ml }
                        }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
