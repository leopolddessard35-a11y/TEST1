import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    ProfileForm(profile: profile)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

private struct ProfileForm: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Bindable var profile: AthleteProfile

    var body: some View {
        Form {
            Section("Objectif") {
                TextField("Course", text: $profile.raceName)
                DatePicker("Date", selection: $profile.raceDate, displayedComponents: .date)
                Stepper("Condition visée : \(profile.targetRaceCTL.noDecimal)", value: $profile.targetRaceCTL, in: 30...100, step: 5)
            }
            Section {
                Stepper("Heures dispo / semaine : \(profile.weeklyHoursAvailable.oneDecimal)", value: $profile.weeklyHoursAvailable, in: 3...20, step: 0.5)
                Stepper("Séances muscu / semaine : \(profile.strengthSessionsPerWeek)", value: $profile.strengthSessionsPerWeek, in: 0...6)
                Stepper("Besoin de sommeil : \(profile.sleepNeedHours.oneDecimal) h", value: $profile.sleepNeedHours, in: 6...10, step: 0.25)
            } header: {
                Text("Disponibilités")
            }
            Section {
                numberField("FTP (W)", value: $profile.ftp)
                numberField("FC seuil vélo (bpm)", value: $profile.cyclingLTHR)
                numberField("FC seuil course (bpm)", value: $profile.runningLTHR)
                numberField("FC max (bpm)", value: $profile.maxHeartRate)
                numberField("Poids (kg)", value: $profile.weightKg)
            } header: {
                Text("Seuils")
            } footer: {
                Text("0 = inconnu. La FTP sert à calculer la charge de tes sorties avec puissance. Re-teste-la dès que ta blessure le permet.")
            }
            Section("Sources de données") {
                Button {
                    Task { await app.syncHealth(context: context) }
                } label: {
                    Label(app.isSyncing ? "Synchronisation…" : "Connecter / synchroniser Apple Santé", systemImage: "heart.text.square.fill")
                }
                .disabled(app.isSyncing)
                Label("Hevy : import CSV depuis l'onglet Entraînement", systemImage: "dumbbell")
                Label("Intervals.icu (Garmin complet) : prochaine étape", systemImage: "link")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Charger des données de démo") {
                    try? DemoData.load(into: context)
                    app.statusMessage = "Données de démo chargées : 4 mois de sommeil, vélo et muscu PPL."
                }
                Button("Effacer toutes les données", role: .destructive) {
                    try? DemoData.clear(context)
                }
            } header: {
                Text("Démo")
            } footer: {
                Text("Pour essayer l'app dans le simulateur, sans iPhone ni Apple Santé. « Effacer » supprime les séances et mesures, pas ton profil.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .onDisappear { try? context.save() }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}
