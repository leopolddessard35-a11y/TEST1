import SwiftUI
import SwiftData

/// Premier lancement, en 3 écrans : ton objectif, Apple Santé, Garmin. Tout reste modifiable dans Réglages.
struct OnboardingView: View {
    @Query private var profiles: [AthleteProfile]
    let onFinish: () -> Void

    var body: some View {
        if let profile = profiles.first {
            OnboardingFlow(profile: profile, onFinish: onFinish)
        } else {
            ProgressView()
        }
    }
}

private struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Bindable var profile: AthleteProfile
    let onFinish: () -> Void

    @State private var step = 0
    @State private var hasRace = true
    @State private var healthAsked = false
    @State private var healthError: String?
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Trois points : où tu en es.
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Theme.accent : Theme.well)
                            .frame(width: index == step ? 22 : 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Étape \(step + 1) sur 3")
                Spacer()
                Button("Passer") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0: goalStep
                    case 1: healthStep
                    default: garminStep
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy, value: step)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 12) {
                if step > 0 {
                    Button("Retour") { withAnimation(.snappy) { step -= 1 } }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                Button(step == 2 ? "Commencer" : "Continuer") { next() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(AppBackground())
        .onAppear { apiKey = app.intervalsAPIKey }
    }

    // MARK: 1. Objectif

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "flag.checkered", title: "Ton objectif",
                   text: "Vigor construit ta saison vers ta course et adapte chaque semaine à ce que tu fais vraiment.")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("J'ai une course en vue", isOn: $hasRace)
                    if hasRace {
                        TextField("Nom de la course (ex. The Traka 100)", text: $profile.raceName)
                            .textFieldStyle(.roundedBorder)
                        DatePicker("Date", selection: $profile.raceDate, in: Date.now..., displayedComponents: .date)
                    } else {
                        Text("Pas de plan de saison : Vigor suit et analyse simplement ce que tu fais.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ton poids").font(.headline)
                    Picker("Objectif de poids", selection: goalBinding) {
                        ForEach(WeightGoal.allCases) { goal in Text(goal.label).tag(goal) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        DecimalFieldNonOptional("Poids (kg)", value: $profile.weightKg)
                            .textFieldStyle(.roundedBorder)
                        DecimalFieldNonOptional("Taille (cm)", value: $profile.heightCm, keyboard: .numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ta semaine type").font(.headline)
                    Stepper("Séances vélo : \(profile.bikeSessionsPerWeek)", value: $profile.bikeSessionsPerWeek, in: 1...7)
                    Stepper("Séances muscu : \(profile.strengthSessionsPerWeek)", value: $profile.strengthSessionsPerWeek, in: 0...6)
                    Text("Total : \(profile.bikeSessionsPerWeek + profile.strengthSessionsPerWeek) séances par semaine. Tu choisis les jours dans Sport → Ma semaine.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 2. Apple Santé

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "heart.text.square.fill", title: "Apple Santé",
                   text: "Ta montre y écrit ton sommeil, ta VFC, ta FC au repos et tes séances : c'est la base de tes scores de récupération et de sommeil.")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("moon.zzz.fill", "Sommeil et stades, siestes à part")
                    bullet("waveform.path.ecg", "VFC, FC au repos, respiration")
                    bullet("figure.outdoor.cycle", "Séances, pas, énergie active")
                    bullet("scalemass.fill", "Poids et VO2max")
                    Text("Vigor lit seulement : il n'écrit rien dans Apple Santé.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                Task {
                    do {
                        try await app.health.requestAuthorization()
                        healthAsked = true
                        healthError = nil
                    } catch {
                        healthError = error.localizedDescription
                    }
                }
            } label: {
                Label(healthAsked ? "Accès demandé" : "Autoriser Apple Santé",
                      systemImage: healthAsked ? "checkmark.circle.fill" : "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(healthAsked ? Theme.good : Theme.accent)
            .controlSize(.large)
            if let healthError {
                Text(healthError).font(.footnote).foregroundStyle(Theme.alert)
            }
            Text("Dans la fenêtre d'iOS, touche « Tout activer ». Tu pourras changer d'avis dans Réglages iPhone → Santé → Accès aux données.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: 3. Garmin

    private var garminStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "applewatch.side.right", title: "Garmin",
                   text: "Via Intervals.icu (gratuit), Vigor récupère tes séances complètes (puissance, zones), la VFC nocturne Garmin et le score de sommeil.")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    stepRow(1, "Crée un compte sur intervals.icu et relie Garmin Connect (Settings → Connections).")
                    stepRow(2, "Settings → Developer Settings : copie l'« Athlete ID » et génère une « API Key ».")
                    stepRow(3, "Colle-les ci-dessous : un an d'historique est importé.")
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Athlete ID (ex. i123456)", text: $profile.intervalsAthleteID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }
            }
            Text("Pas de Garmin, ou plus tard ? Touche « Commencer » : tu pourras l'ajouter dans Réglages → Connexions.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Éléments

    private func header(symbol: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Theme.well, in: .circle)
                .accessibilityHidden(true)
            Text(title).font(.largeTitle.weight(.bold))
            Text(text).font(.body).foregroundStyle(.secondary)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.subheadline)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.accent, in: .circle)
            Text(text).font(.subheadline)
        }
    }

    private var goalBinding: Binding<WeightGoal> {
        Binding {
            profile.weightGoal
        } set: { goal in
            profile.weightGoalRaw = goal.rawValue
            profile.calorieAdjustment = goal.suggestedAdjustment
        }
    }

    // MARK: Navigation

    private func next() {
        if step < 2 {
            if step == 0, !hasRace { profile.raceName = "" }
            withAnimation(.snappy) { step += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        if !hasRace { profile.raceName = "" }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { app.intervalsAPIKey = key }
        try? context.save()
        app.dataVersion += 1
        onFinish()
    }
}
