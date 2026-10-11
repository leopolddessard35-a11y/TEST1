import SwiftUI
import SwiftData
import UserNotifications

/// Les 4 groupes de réglages.
enum SettingsPage: String, Hashable {
    case profile, connections, notifications, data
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [AthleteProfile]
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.light.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("Apparence") {
                    Picker("Apparence", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                if let profile = profiles.first {
                    Section {
                        link(profile, .profile, "Profil et objectif", "person.crop.circle", "Course, morphologie, seuils, disponibilités")
                        NavigationLink {
                            NutritionGoalsView()
                        } label: {
                            rowLabel("Objectif nutrition", "fork.knife", "Prise de poids, calories et macros")
                        }
                        link(profile, .connections, "Connexions", "link", "Garmin via Intervals.icu, Apple Santé")
                        link(profile, .notifications, "Notifications", "bell", "Plan du matin, repas, alertes")
                        link(profile, .data, "Données", "externaldrive", "Aliments CIQUAL, chaussures, export")
                    }
                } else {
                    ProgressView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Réglages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func link(_ profile: AthleteProfile, _ page: SettingsPage, _ title: String, _ symbol: String, _ detail: String) -> some View {
        NavigationLink {
            ProfileForm(profile: profile, page: page)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            rowLabel(title, symbol, detail)
        }
    }

    private func rowLabel(_ title: String, _ symbol: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.accent.gradient, in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProfileForm: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var profile: AthleteProfile
    let page: SettingsPage
    @State private var apiKey = ""
    @State private var notificationsDenied = false
    /// Autorisation jamais demandée : elle l'est quand tu actives un rappel (jamais au premier lancement).
    @State private var notificationsUndetermined = false
    @State private var confirmLoadDemo = false
    @State private var confirmClearData = false
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
            if page == .profile {
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
                // Rien n'est écrit tant que tu ne choisis pas ; les années récentes en premier.
                Picker("Année de naissance", selection: $profile.birthYear) {
                    Text("Non renseignée").tag(0)
                    ForEach(Array((1940...Self.latestBirthYear).reversed()), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                numberField("Poids (kg)", value: $profile.weightKg)
            } header: {
                Text("Morphologie")
            } footer: {
                Text("Utilisés pour le métabolisme de base (Mifflin-St Jeor). Le poids synchronisé depuis Garmin / Apple Santé est prioritaire.")
            }
            Section {
                Stepper("Heures dispo / semaine : \(profile.weeklyHoursAvailable.oneDecimal)", value: $profile.weeklyHoursAvailable, in: 3...20, step: 0.5)
                Stepper("Séances vélo / semaine : \(profile.bikeSessionsPerWeek)", value: $profile.bikeSessionsPerWeek, in: 1...7)
                Stepper("Séances muscu / semaine : \(profile.strengthSessionsPerWeek)", value: $profile.strengthSessionsPerWeek, in: 0...6)
                Stepper("Besoin de sommeil : \(profile.sleepNeedHours.oneDecimal) h", value: $profile.sleepNeedHours, in: 6...10, step: 0.25)
            } header: {
                Text("Disponibilités")
            } footer: {
                Text("Total : \(profile.bikeSessionsPerWeek + profile.strengthSessionsPerWeek) séances par semaine. Les séances vélo comprennent la sortie longue et l'intensité ; le volume se répartit sur ce nombre. La muscu est un peu réduite en développement et avant la course.")
            }
            Section {
                numberField("FTP (W)", value: $profile.ftp)
                numberField("FC seuil vélo (bpm)", value: $profile.cyclingLTHR)
                numberField("FC seuil course (bpm)", value: $profile.runningLTHR)
                numberField("FC max (bpm)", value: $profile.maxHeartRate)
            } header: {
                Text("Seuils")
            } footer: {
                Text("0 = inconnu. La FTP sert à calculer la charge de tes sorties avec puissance. Re-teste-la régulièrement pour garder des zones justes.")
            }
            }
            if page == .connections {
            Section {
                SecureField("Clé d'API", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { keepTypedAPIKey(announce: true) }
                TextField("Identifiant athlète (ex. i123456)", text: $profile.intervalsAthleteID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enregistrer la clé") { saveAPIKey() }
            } header: {
                Text("Garmin via Intervals.icu")
            } footer: {
                Text("1. Crée un compte gratuit sur intervals.icu et relie Garmin Connect (Settings → Connections).\n2. Settings → Developer Settings : copie l'« Athlete ID » et génère une « API Key ».\n3. Colle-les ici : la première clé lance la synchro d'un an d'historique. Tu récupères tes séances complètes, la VFC nocturne, le score de sommeil, la récupération Garmin et ton calendrier d'entraînement.")
            }
            }
            if page == .notifications {
            if notificationsUndetermined {
                Section {
                    Button("Autoriser les notifications") { askNotificationPermission() }
                } footer: {
                    Text("Vigor ne te le demande qu'une fois, ici ou quand tu actives un rappel : iOS affiche alors sa demande d'autorisation. Sans elle, aucun rappel n'arrive.")
                }
            }
            if notificationsDenied {
                Section {
                    Label("Les notifications sont désactivées pour Vigor dans les réglages de l'iPhone : aucun rappel ne sera affiché.", systemImage: "bell.slash")
                        .foregroundStyle(Theme.warning)
                    Button("Ouvrir les réglages de l'iPhone") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
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
                    .onChange(of: alertsEnabled) { _, isOn in notificationToggled(isOn) }
                mealRow("Petit-déjeuner", isOn: $breakfastEnabled, minutes: $breakfastMinutes)
                mealRow("Déjeuner", isOn: $lunchEnabled, minutes: $lunchMinutes)
                mealRow("Goûter", isOn: $snackEnabled, minutes: $snackMinutes)
                mealRow("Dîner", isOn: $dinnerEnabled, minutes: $dinnerMinutes)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Matin : verdict du jour, séance adaptée à ta nuit et ta récup, priorité n° 1. Repas : quantités visées (ce qu'il reste à manger aujourd'hui) et conseil selon tes séances ; pas de rappel si le repas est déjà noté. Soir : protéines ou calories manquantes, préparation du lendemain. Alertes importantes : uniquement les seuils critiques (surcharge, dette de sommeil, symptôme récurrent, surmenage), une fois par jour au maximum. Activer un rappel demande l'autorisation d'iOS la première fois.")
            }
            }
            if page == .profile {
                AgendaSection(profile: profile)
            }
            if page == .data {
                Section("Nutrition") {
                    NavigationLink {
                        CiqualImportView()
                    } label: {
                        Label("Aliments génériques (CIQUAL)", systemImage: "leaf.fill")
                    }
                }
                ShoesSection()
                ExportSection()
            }
            if page == .connections {
            Section("Synchronisation") {
                Button {
                    Task { await app.syncAll(context: context, profile: profile) }
                } label: {
                    Label(app.isSyncing ? "Synchronisation…" : "Tout synchroniser (Apple Santé + Intervals.icu)", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(app.isSyncing)
                Label("Musculation : séances dans Sport → Musculation (historique Hevy importable une fois)", systemImage: "dumbbell")
            }
            }
            #if DEBUG
            if page == .data {
            Section {
                Button("Charger des données de démo") { confirmLoadDemo = true }
                    .confirmationDialog("Charger les données de démo ?", isPresented: $confirmLoadDemo, titleVisibility: .visible) {
                        Button("Remplacer mes données par la démo", role: .destructive) { loadDemo() }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Toutes tes données actuelles (séances, mesures, repas, aliments, programmes…) seront effacées puis remplacées. Ton profil est conservé.")
                    }
                Button("Effacer toutes les données", role: .destructive) { confirmClearData = true }
                    .confirmationDialog("Effacer toutes les données ?", isPresented: $confirmClearData, titleVisibility: .visible) {
                        Button("Tout effacer", role: .destructive) { clearData() }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Séances, mesures, repas, aliments, programmes, exercices et expériences seront supprimés définitivement. Ton profil est conservé.")
                    }
            } header: {
                Text("Démo")
            } footer: {
                Text("Pour essayer l'app dans le simulateur, sans iPhone ni Apple Santé. « Effacer » supprime séances, mesures, repas, aliments, programmes et expériences, pas ton profil.")
            }
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .onAppear { apiKey = app.intervalsAPIKey }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNotificationStatus() } }
        }
        .onChange(of: morningEnabled) { _, isOn in notificationToggled(isOn) }
        .onChange(of: eveningEnabled) { _, isOn in notificationToggled(isOn) }
        .onDisappear {
            // Clé tapée sans « Enregistrer » : elle n'est pas perdue.
            keepTypedAPIKey(announce: false)
            try? context.save()
            app.dataVersion += 1
        }
    }

    /// Année la plus récente proposée (12 ans).
    private static var latestBirthYear: Int { Calendar.current.component(.year, from: .now) - 12 }

    /// Bouton « Enregistrer la clé » : enregistre (ou supprime si vide).
    private func saveAPIKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFirstKey = app.intervalsAPIKey.isEmpty && !key.isEmpty
        app.intervalsAPIKey = key
        if key.isEmpty {
            app.statusMessage = "Clé supprimée."
        } else {
            app.statusMessage = isFirstKey
                ? "Clé enregistrée dans le trousseau sécurisé de l'iPhone. Synchronisation d'un an d'historique en cours…"
                : "Clé enregistrée dans le trousseau sécurisé de l'iPhone."
        }
        if isFirstKey { syncFullHistory() }
    }

    /// Validation au clavier ou départ de l'écran : enregistre une clé non vide et modifiée.
    private func keepTypedAPIKey(announce: Bool) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != app.intervalsAPIKey else { return }
        if announce {
            saveAPIKey()
            return
        }
        let isFirstKey = app.intervalsAPIKey.isEmpty
        app.intervalsAPIKey = key
        if isFirstKey { syncFullHistory() }
    }

    /// Première clé : un an d'historique d'un coup (même synchro que « Tout synchroniser »), pas 30 jours.
    private func syncFullHistory() {
        Task { await app.syncAll(context: context, profile: profile) }
    }

    /// Rappel activé : demande l'autorisation la première fois, puis reprogramme.
    private func notificationToggled(_ isOn: Bool) {
        app.dataVersion += 1
        if isOn { askNotificationPermission() }
    }

    private func askNotificationPermission() {
        Task {
            await NotificationScheduler.requestAuthorizationIfNeeded()
            await refreshNotificationStatus()
            app.dataVersion += 1
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
        notificationsUndetermined = settings.authorizationStatus == .notDetermined
    }

    #if DEBUG
    private func loadDemo() {
        do {
            try DemoData.load(into: context)
            app.statusMessage = "Données de démo chargées : 4 mois de sommeil, VFC, vélo, muscu PPL et repas."
        } catch {
            app.statusMessage = "Chargement de la démo impossible : \(error.localizedDescription)"
        }
        app.dataVersion += 1
    }

    private func clearData() {
        do {
            try DemoData.clear(context)
            app.statusMessage = "Toutes les données ont été effacées (profil conservé)."
        } catch {
            app.statusMessage = "Effacement impossible : \(error.localizedDescription)"
        }
        app.dataVersion += 1
    }
    #endif

    @ViewBuilder
    private func mealRow(_ title: String, isOn: Binding<Bool>, minutes: Binding<Int>) -> some View {
        Toggle("Rappel \(title.lowercased())", isOn: isOn)
            .onChange(of: isOn.wrappedValue) { _, isOn in notificationToggled(isOn) }
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
            DecimalFieldNonOptional(title, value: value)
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Options de \(shoe.name)")
                }
            }
            HStack {
                TextField("Nouvelle paire", text: $name)
                DecimalFieldNonOptional("km déjà faits", value: $initialKm)
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
            Text("Toutes tes données restent sur ton iPhone. L'export contient santé quotidienne (Apple Santé et Garmin), séances, séries de muscu, séances types, exercices et aliments créés, repas, objectifs, indisponibilités, blessures, chaussures, profil, symptômes, activités hors sport, et les versions des formules utilisées. CSV lisibles dans Excel en français (« ; » et virgule décimale).")
        }
    }
}
