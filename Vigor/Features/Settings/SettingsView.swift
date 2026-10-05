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
    @State private var apiKey = ""
    @AppStorage(NotificationScheduler.Keys.morningEnabled) private var morningEnabled = true
    @AppStorage(NotificationScheduler.Keys.morningMinutes) private var morningMinutes = 7 * 60 + 15
    @AppStorage(NotificationScheduler.Keys.eveningEnabled) private var eveningEnabled = true
    @AppStorage(NotificationScheduler.Keys.eveningMinutes) private var eveningMinutes = 20 * 60 + 30

    var body: some View {
        Form {
            Section("Objectif") {
                TextField("Course", text: $profile.raceName)
                DatePicker("Date", selection: $profile.raceDate, displayedComponents: .date)
                Stepper("Condition visée : \(profile.targetRaceCTL.noDecimal)", value: $profile.targetRaceCTL, in: 30...100, step: 5)
            }
            Section {
                Picker("Sexe", selection: $profile.sexRaw) {
                    ForEach(Sex.allCases) { Text($0.label).tag($0.rawValue) }
                }
                numberField("Taille (cm)", value: $profile.heightCm)
                Stepper("Année de naissance : \(profile.birthYear > 0 ? String(profile.birthYear) : "–")",
                        value: $profile.birthYear, in: 1940...2015)
                    .onAppear { if profile.birthYear == 0 { profile.birthYear = 1995 } }
                numberField("Poids (kg)", value: $profile.weightKg)
            } header: {
                Text("Morphologie")
            } footer: {
                Text("Utilisés pour le métabolisme de base (Mifflin-St Jeor). Le poids synchronisé depuis Garmin / Apple Santé est prioritaire.")
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
            } header: {
                Text("Seuils")
            } footer: {
                Text("0 = inconnu. La FTP sert à calculer la charge de tes sorties avec puissance. Re-teste-la dès que ta blessure le permet.")
            }
            Section {
                SecureField("Clé d'API", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Identifiant athlète (ex. i123456)", text: $profile.intervalsAthleteID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enregistrer la clé") {
                    app.intervalsAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    app.statusMessage = apiKey.isEmpty ? "Clé supprimée." : "Clé enregistrée dans le trousseau sécurisé de l'iPhone."
                }
            } header: {
                Text("Garmin via Intervals.icu")
            } footer: {
                Text("1. Crée un compte gratuit sur intervals.icu et relie Garmin Connect (Settings → Connections).\n2. Settings → Developer Settings : copie l'« Athlete ID » et génère une « API Key ».\n3. Colle-les ici, puis synchronise. Tu récupères tes séances complètes, la VFC nocturne, le score de sommeil, la readiness Garmin et ton calendrier d'entraînement.")
            }
            Section {
                Toggle("Plan du matin", isOn: $morningEnabled)
                if morningEnabled {
                    DatePicker("Heure", selection: timeBinding($morningMinutes), displayedComponents: .hourAndMinute)
                }
                Toggle("Bilan du soir", isOn: $eveningEnabled)
                if eveningEnabled {
                    DatePicker("Heure", selection: timeBinding($eveningMinutes), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Matin : verdict du jour, séance adaptée à ta nuit et ta récup, priorité n° 1. Soir : protéines ou calories manquantes, préparation de la séance du lendemain (glucides, coucher).")
            }
            Section("Synchronisation") {
                Button {
                    Task { await app.syncAll(context: context, profile: profile) }
                } label: {
                    Label(app.isSyncing ? "Synchronisation…" : "Tout synchroniser (Apple Santé + Intervals.icu)", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(app.isSyncing)
                Label("Hevy : import CSV depuis l'onglet Entraînement", systemImage: "dumbbell")
            }
            Section {
                Button("Charger des données de démo") {
                    try? DemoData.load(into: context)
                    app.dataVersion += 1
                    app.statusMessage = "Données de démo chargées : 4 mois de sommeil, VFC, vélo, muscu PPL et repas."
                }
                Button("Effacer toutes les données", role: .destructive) {
                    try? DemoData.clear(context)
                    app.dataVersion += 1
                }
            } header: {
                Text("Démo")
            } footer: {
                Text("Pour essayer l'app dans le simulateur, sans iPhone ni Apple Santé. « Effacer » supprime séances, mesures et repas, pas ton profil.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .onAppear { apiKey = app.intervalsAPIKey }
        .onChange(of: morningEnabled) { app.dataVersion += 1 }
        .onChange(of: eveningEnabled) { app.dataVersion += 1 }
        .onDisappear { try? context.save() }
    }

    /// Convertit des minutes après minuit en heure pour le sélecteur.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue, to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                app.dataVersion += 1
            })
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
