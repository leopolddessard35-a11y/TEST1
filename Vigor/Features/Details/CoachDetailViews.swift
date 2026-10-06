import SwiftUI
import Charts

// MARK: - Récupération

struct ReadinessDetailView: View {
    let readiness: ReadinessResult?
    let history: [DayValue]
    let hrvSource: String

    private let weights = ["VFC": "45 %", "FC au repos": "25 %", "Sommeil": "30 %", "Fatigue d'entraînement": "malus"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let readiness {
                    GlassCard {
                        HStack(spacing: 20) {
                            ScoreRing(value: Double(readiness.score), color: Theme.color(for: readiness.level), label: "sur 100")
                                .frame(width: 120, height: 120)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(readiness.level.label).font(.title3.weight(.semibold))
                                Text(readiness.level.advice).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Ce qui compose ton score", symbol: "chart.bar.doc.horizontal")
                            ForEach(readiness.components) { component in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(component.name).font(.subheadline.weight(.semibold))
                                        Text(weights[component.name] ?? "").font(.caption).foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(component.score))/100").font(.subheadline.monospacedDigit())
                                    }
                                    AnimatedBar(fraction: component.score / 100,
                                                color: component.score >= 70 ? Theme.recovery : (component.score >= 45 ? Theme.nutrition : Theme.warning))
                                    Text(component.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateCard(title: "Score indisponible",
                                   message: "Il faut au moins 14 nuits de VFC ou ta nuit de sommeil. Synchronise Apple Santé et Intervals.icu.",
                                   symbol: "heart.text.square")
                }

                if !history.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "30 derniers jours", symbol: "calendar")
                            Chart(history, id: \.date) { point in
                                BarMark(x: .value("Jour", point.date, unit: .day), y: .value("Score", point.value))
                                    .foregroundStyle(point.value >= 70 ? Theme.recovery : (point.value >= 45 ? Theme.nutrition : Theme.warning))
                                    .cornerRadius(3)
                            }
                            .chartYScale(domain: 0...100)
                            .frame(height: 160)
                        }
                    }
                }

                ExplanationCard(title: "Comment c'est calculé", symbol: "function", text: """
                Chaque mesure est comparée à TA propre normale, pas à une moyenne de population :
                • VFC (\(hrvSource)) : moyenne des 3 derniers jours en logarithme, comparée à tes 60 derniers jours. Un écart d'un écart-type déplace le score de 20 points.
                • FC au repos : dernière nuit comparée à tes 30 derniers jours (plus haut = moins bien).
                • Sommeil : durée de la nuit rapportée à ton besoin (réglable dans Réglages).
                • Fatigue : si ta forme (TSB) passe sous −25, le score est pénalisé.
                ≥ 70 : prêt à charger · 45–69 : modéré · < 45 : récupération basse.
                """)
                ReferencesCard(references: [Science.plews2013, Science.buchheit2014, Science.kiviniemi2007, Science.hirshkowitz2015])
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Récupération")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Charge

struct LoadDetailView: View {
    let load: [LoadPoint]
    var disciplines: [DisciplineLoad] = []
    var volumes: [WeeklyVolume] = []
    var alerts: [String] = []
    var lifeLoad7: Double = 0
    @State private var days = 90

    var body: some View {
        let visible = Array(load.suffix(days))
        let last7 = load.suffix(7).map(\.tss)
        let last28 = load.suffix(28).map(\.tss)
        let acute = last7.reduce(0, +) / 7
        let chronic = last28.reduce(0, +) / 28
        let monotony: Double? = {
            guard let mean = Stats.mean(last7), let sd = Stats.standardDeviation(last7), sd > 0 else { return nil }
            return mean / sd
        }()

        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        RangePicker(days: $days)
                        Chart {
                            ForEach(visible) { point in
                                LineMark(x: .value("Jour", point.date), y: .value("Valeur", point.ctl))
                                    .foregroundStyle(by: .value("Courbe", "Condition"))
                                LineMark(x: .value("Jour", point.date), y: .value("Valeur", point.atl))
                                    .foregroundStyle(by: .value("Courbe", "Fatigue"))
                                AreaMark(x: .value("Jour", point.date), y: .value("Valeur", point.form))
                                    .foregroundStyle(by: .value("Courbe", "Forme"))
                                    .opacity(0.35)
                            }
                        }
                        .chartForegroundStyleScale(["Condition": Theme.recovery, "Fatigue": Theme.strain, "Forme": Theme.sleep])
                        .frame(height: 240)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Condition (CTL)", value: load.last?.ctl.noDecimal ?? "–", caption: "moyenne 42 j")
                    StatTile(title: "Fatigue (ATL)", value: load.last?.atl.noDecimal ?? "–", caption: "moyenne 7 j")
                    StatTile(title: "Forme (TSB)", value: load.last?.form.noDecimal ?? "–", caption: "−10 à −30 : progression")
                    StatTile(title: "Progression 7 j", value: TrainingLoad.rampRate(load).map { String(format: "%+.1f", $0) } ?? "–", caption: "repère : ≤ +5")
                    StatTile(title: "Ratio aigu/chronique", value: chronic > 0 ? String(format: "%.2f", acute / chronic) : "–", caption: "zone sûre : 0,8–1,3")
                    StatTile(title: "Monotonie", value: monotony.map { String(format: "%.1f", $0) } ?? "–", caption: "repère : < 2")
                }

                if !disciplines.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(title: "Par discipline · 7 j vs 28 j", symbol: "square.grid.2x2")
                            HStack {
                                Text("").frame(maxWidth: .infinity, alignment: .leading)
                                Text("7 j").frame(width: 50)
                                Text("28 j").frame(width: 50)
                                Text("Ratio").frame(width: 56)
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(disciplines) { item in
                                HStack {
                                    Text(item.name).font(.subheadline.weight(item.name == "Global" ? .bold : .regular))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.acute.noDecimal).frame(width: 50)
                                    Text(item.chronic.noDecimal).frame(width: 50)
                                    Text(item.ratio.map { String(format: "%.2f", $0) } ?? "–")
                                        .foregroundStyle(LoadDetailView.ratioColor(item.ratio))
                                        .frame(width: 56)
                                }
                                .font(.subheadline.monospacedDigit())
                            }
                            Text(String(format: "TSS moyen par jour. La charge hors sport (travaux, journées debout, pas > 12 000) compte : %.0f TSS sur 7 jours.", lifeLoad7))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if !volumes.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(title: "Volume hebdomadaire", symbol: "calendar")
                            HStack {
                                Text("Semaine").frame(maxWidth: .infinity, alignment: .leading)
                                Text("Vélo").frame(width: 54)
                                Text("Course").frame(width: 54)
                                Text("Muscu").frame(width: 54)
                                Text("Hors sport").frame(width: 64)
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(volumes.reversed()) { week in
                                HStack {
                                    Text(week.weekStart.formatted(.dateTime.day().month(.abbreviated))).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(week.bikeHours.hoursText).frame(width: 54)
                                    Text(String(format: "%.0f km", week.runKm)).frame(width: 54)
                                    Text(String(format: "%.1f t", week.tonnage / 1000)).frame(width: 54)
                                    Text(week.lifeHours.hoursText).frame(width: 64)
                                }
                                .font(.caption.monospacedDigit())
                            }
                            ForEach(alerts, id: \.self) { alert in
                                Label(alert, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.nutrition)
                            }
                            Text("Repère : ne pas augmenter le volume de plus d'environ 10 % d'une semaine à l'autre.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                ExplanationCard(title: "Comment c'est calculé", symbol: "function", text: """
                • Chaque séance reçoit un TSS : 100 = 1 h à ta FTP. Avec puissance : durée × (puissance normalisée / FTP)² × 100. Sans puissance : même formule avec ta FC rapportée à ta FC seuil. Musculation : ~40 TSS/h.
                • Condition (CTL) : moyenne exponentielle de la charge sur 42 jours, c'est ton « moteur ».
                • Fatigue (ATL) : même chose sur 7 jours.
                • Forme (TSB) = condition − fatigue de la veille. Une course se prépare pour arriver entre +5 et +20.
                • Ratio aigu/chronique : charge des 7 derniers jours / charge des 28 derniers jours.
                • Monotonie (Foster) : moyenne / écart-type de la charge quotidienne sur 7 jours.
                """)
                ReferencesCard(references: [Science.banister1975, Science.allenCoggan, Science.gabbett2016, Science.foster1998])
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Charge d'entraînement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension LoadDetailView {
    static func ratioColor(_ ratio: Double?) -> Color {
        guard let ratio else { return .secondary }
        if ratio > 1.5 { return Theme.warning }
        if ratio > 1.3 || ratio < 0.8 { return Theme.nutrition }
        return Theme.recovery
    }
}

// MARK: - Analyse du coach

struct InsightsView: View {
    let insights: [Insight]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if insights.isEmpty {
                    EmptyStateCard(title: "Rien à signaler",
                                   message: "Le coach n'a pas assez de données ou tout est dans la norme. Plus tu synchronises de données (sommeil, VFC, séances, repas, poids), plus l'analyse est fine.",
                                   symbol: "checkmark.seal")
                }
                ForEach(Insight.Category.allCases, id: \.self) { category in
                    let items = insights.filter { $0.category == category }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.label).font(.headline).padding(.leading, 4)
                            ForEach(items) { InsightCard(insight: $0, expanded: false) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Analyse du coach")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct InsightCard: View {
    let insight: Insight
    @State var expanded: Bool

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.severity.symbol)
                            .foregroundStyle(InsightCard.color(insight.severity))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                            Text(insight.severity.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ce que disent tes données").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(insight.evidence, id: \.self) { line in
                            Text("• \(line)").font(.footnote.monospacedDigit())
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ce que je te conseille").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(insight.recommendation).font(.footnote)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pourquoi").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(insight.references) { reference in
                            Text(reference.finding).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    static func color(_ severity: Insight.Severity) -> Color {
        switch severity {
        case .positive: Theme.recovery
        case .info: Theme.sleep
        case .watch: Theme.nutrition
        case .warning: Theme.warning
        }
    }
}

// MARK: - Semaine

struct WeekDetailView: View {
    let week: PlannedWeek

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(week.phase.label) · semaine \(week.kind.label.lowercased())").font(.title3.weight(.semibold))
                        Text(week.phase.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Volume vélo", value: week.targetHours.hoursText)
                    StatTile(title: "Charge visée", value: "\(week.targetTSS.noDecimal) TSS")
                    StatTile(title: "Sortie longue", value: week.longRideHours > 0 ? week.longRideHours.hoursText : "–")
                    StatTile(title: "Séances intenses", value: "\(week.intensitySessions)")
                    StatTile(title: "Muscu PPL", value: "\(week.strengthSessions)×")
                    StatTile(title: "Jours disponibles", value: "\(week.availableDays)/7")
                }
                if !week.notes.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(title: "Adaptations de la semaine", symbol: "wand.and.stars")
                            ForEach(week.notes, id: \.self) { Text("• \($0)").font(.footnote) }
                        }
                    }
                }
                ExplanationCard(title: "Nutrition de la phase", symbol: "fork.knife", text: week.phase.nutritionFocus)
                ExplanationCard(title: "Comment le plan est construit", symbol: "function", text: """
                • La condition progresse au maximum de +3 (reprise) à +5 points par semaine : au-delà, le risque de blessure augmente nettement.
                • 3 semaines de charge, puis 1 semaine de récupération (−40 %).
                • ~80 % du volume à basse intensité, 1 à 2 séances intenses par semaine selon la phase.
                • Affûtage final : volume réduit de ~40 % en gardant un peu d'intensité.
                • Le plan est recalculé à chaque ouverture depuis ta condition réelle : une semaine ratée n'est jamais « rattrapée ».
                """)
                ReferencesCard(references: [Science.seiler2010, Science.gabbett2016, Science.mujika2003, Science.bosquet2007, Science.wilson2012])
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Semaine du \(week.start.formatted(.dateTime.day().month(.abbreviated)))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Objectifs nutritionnels

struct MacroTargetsDetailView: View {
    let targets: MacroTargets
    let today: NutritionDay

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Calories", value: "\(today.kcal.noDecimal) / \(targets.kcal.noDecimal)", caption: "kcal")
                    StatTile(title: "Protéines", value: "\(today.protein.noDecimal) / \(targets.protein.noDecimal)", caption: "g")
                    StatTile(title: "Glucides", value: "\(today.carbs.noDecimal) / \(targets.carbs.noDecimal)", caption: "g")
                    StatTile(title: "Lipides", value: "\(today.fat.noDecimal) / \(targets.fat.noDecimal)", caption: "g")
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "Le calcul, étape par étape", symbol: "function")
                        Text("Dépense du jour (\(targets.expenditureMethod)) : \(targets.expenditure.noDecimal) kcal").font(.subheadline.weight(.semibold))
                        ForEach(targets.explanation, id: \.self) { Text("• \($0)").font(.footnote) }
                    }
                }
                ExplanationCard(title: "Dépense mesurée", symbol: "scalemass", text: "Après 3 semaines de repas renseignés et de pesées régulières, Vigor remplace la formule par ta dépense RÉELLE : apports moyens − variation de ton poids lissé × 7 700 kcal/kg. C'est plus fiable que n'importe quelle montre.")
                ReferencesCard(references: [Science.mifflin1990, Science.morton2018, Science.burke2011, Science.iraki2019, Science.hall2008, Science.jeukendrup2014])
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Objectifs du jour")
        .navigationBarTitleDisplayMode(.inline)
    }
}
