import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

private struct ProfileForm: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Bindable var profile: AthleteProfile
    @State private var apiKey = ""
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.light.rawValue
    @AppStorage(NotificationScheduler.Keys.morningEnabled) private var morningEnabled = true
    @AppStorage(NotificationScheduler.Keys.morningMinutes) private var morningMinutes = 7 * 60 + 15
    @AppStorage(NotificationScheduler.Keys.eveningEnabled) private var eveningEnabled = false
    @AppStorage(NotificationScheduler.Keys.alertsEnabled) private var alertsEnabled = true
    @AppStorage(NotificationScheduler.Keys.eveningMinutes) private var eveningMinutes = 21 * 60 + 30
    @AppStorage(NotificationScheduler.Keys.mealEnabled(.breakfast)) private var breakfastEnabled = false
    @AppStorage(NotificationScheduler.Keys.mealMinutes(.breakfast)) private var breakfastMinutes = NotificationScheduler.defaultMinutes(for: .breakfast)
    @AppStorage(NotificationScheduler.Keys.mealEnabled(.lunch)) private var lunchEnabled = false
    @AppStorage(NotificationScheduler.Keys.mealMinutes(.lunch)) private var lunchMinutes = NotificationScheduler.defaultMinutes(for: .lunch)
    @AppStorage(NotificationScheduler.Keys.mealEnabled(.snack)) private var snackEnabled = false
    @AppStorage(NotificationScheduler.Keys.mealMinutes(.snack)) private var snackMinutes = NotificationScheduler.defaultMinutes(for: .snack)
    @AppStorage(NotificationScheduler.Keys.mealEnabled(.dinner)) private var dinnerEnabled = false
    @AppStorage(NotificationScheduler.Keys.mealMinutes(.dinner)) private var dinnerMinutes = NotificationScheduler.defaultMinutes(for: .dinner)

    var body: some View {
        Form {
            Section("Apparence") {
                Picker("Apparence", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
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
                Toggle("Alertes importantes", isOn: $alertsEnabled)
                    .onChange(of: alertsEnabled) { app.dataVersion += 1 }
                mealRow("Petit-déjeuner", isOn: $breakfastEnabled, minutes: $breakfastMinutes)
                mealRow("Déjeuner", isOn: $lunchEnabled, minutes: $lunchMinutes)
                mealRow("Goûter", isOn: $snackEnabled, minutes: $snackMinutes)
                mealRow("Dîner", isOn: $dinnerEnabled, minutes: $dinnerMinutes)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Matin : verdict du jour, séance adaptée à ta nuit et ta récup, priorité n° 1. Repas : quantités visées (ce qu'il reste à manger aujourd'hui) et conseil selon tes séances ; pas de rappel si le repas est déjà noté. Soir : protéines ou calories manquantes, préparation du lendemain. Alertes importantes : uniquement les seuils critiques (surcharge, dette de sommeil, symptôme récurrent, surmenage), une fois par jour au maximum.")
            }
            AgendaSection(profile: profile)
            ShoesSection()
            ExportSection()
            Section("Synchronisation") {
                Button {
                    Task { await app.syncAll(context: context, profile: profile) }
                } label: {
                    Label(app.isSyncing ? "Synchronisation…" : "Tout synchroniser (Apple Santé + Intervals.icu)", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(app.isSyncing)
                Label("Muscu : séances dans Activité → Muscu (historique Hevy importable une fois)", systemImage: "dumbbell")
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

    @ViewBuilder
    private func mealRow(_ title: String, isOn: Binding<Bool>, minutes: Binding<Int>) -> some View {
        Toggle("Rappel \(title.lowercased())", isOn: isOn)
            .onChange(of: isOn.wrappedValue) { app.dataVersion += 1 }
        if isOn.wrappedValue {
            DatePicker("Heure", selection: timeBinding(minutes), displayedComponents: .hourAndMinute)
        }
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

/// Chaussures de course : kilométrage et paire par défaut.
private struct ShoesSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Shoe.addedAt) private var shoes: [Shoe]
    @State private var name = ""
    @State private var initialKm = 0.0

    var body: some View {
        Section {
            ForEach(shoes) { shoe in
                HStack {
                    VStack(alignment: .leading) {
                        Text(shoe.name).strikethrough(shoe.retired)
                        Text(shoe.isDefault ? "Par défaut" : (shoe.retired ? "Retirée" : "")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Paire par défaut") {
                            for other in shoes { other.isDefault = other.shoeID == shoe.shoeID }
                            save()
                        }
                        Button(shoe.retired ? "Remettre en service" : "Retirer") {
                            shoe.retired.toggle()
                            if shoe.retired { shoe.isDefault = false }
                            save()
                        }
                        Button("Supprimer", role: .destructive) {
                            context.delete(shoe)
                            save()
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            HStack {
                TextField("Nouvelle paire", text: $name)
                TextField("km déjà faits", value: $initialKm, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 90)
                Button("Ajouter") {
                    context.insert(Shoe(name: name, initialKm: initialKm, isDefault: shoes.allSatisfy { $0.retired }))
                    name = ""
                    initialKm = 0
                    save()
                }
                .disabled(name.isEmpty)
            }
        } header: {
            Text("Chaussures de course")
        } footer: {
            Text("Les sorties course sont comptées sur la paire par défaut (modifiable dans le détail de chaque sortie). Alerte au-delà de 600 km.")
        }
    }

    private func save() {
        try? context.save()
        app.dataVersion += 1
    }
}

/// Disponibilités par jour de la semaine : le coach raccourcit les séances au-delà.
private struct AgendaSection: View {
    @Environment(AppModel.self) private var app
    @Bindable var profile: AthleteProfile
    private let names = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]

    var body: some View {
        Section {
            ForEach(0..<7, id: \.self) { index in
                let minutes = profile.weekdayMinutes[index]
                Stepper("\(names[index]) : \(minutes == 0 ? "sans limite" : (Double(minutes) / 60).hoursText)",
                        value: Binding(get: { minutes }, set: { update(index, $0) }), in: 0...360, step: 15)
            }
        } header: {
            Text("Disponibilités par jour")
        } footer: {
            Text("Ex. mercredi et jeudi à 45 min : les séances de ces jours sont raccourcies automatiquement.")
        }
    }

    private func update(_ index: Int, _ value: Int) {
        var values = profile.weekdayMinutes
        values[index] = value
        profile.weekdayMinutesRaw = values.map(String.init).joined(separator: ",")
        app.dataVersion += 1
    }
}

/// Export complet CSV / JSON, et versions des formules.
private struct ExportSection: View {
    @Environment(\.modelContext) private var context
    @State private var files: [URL] = []
    @State private var error: String?

    var body: some View {
        Section {
            Button("Préparer l'export (CSV + JSON)") {
                do { files = try Exporter.exportAll(context: context) } catch { self.error = error.localizedDescription }
            }
            if !files.isEmpty {
                ShareLink(items: files) {
                    Label("Partager \(files.count) fichiers", systemImage: "square.and.arrow.up")
                }
            }
            if let error { Text(error).foregroundStyle(Theme.warning) }
            DisclosureGroup("Versions des formules") {
                ForEach(FormulaVersion.all, id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        } header: {
            Text("Mes données")
        } footer: {
            Text("Toutes tes données restent sur ton iPhone. L'export contient santé quotidienne, séances, séries de muscu, repas, symptômes, activités hors sport, et les versions des formules utilisées.")
        }
    }
}
