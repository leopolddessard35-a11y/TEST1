import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var app
    @Environment(SyncService.self) private var sync
    @Query private var profiles: [AthleteProfile]
    @State private var showSettings = false
    @State private var addingFood = false
    /// Date affichée dans le titre : rafraîchie à minuit et au retour au premier plan.
    @State private var today = Date.now

    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { _, snapshot in
                    // Trois questions, trois cartes : comment je vais, quoi faire, ce qu'il me reste à faire aujourd'hui.
                    // Le reste (mesures, analyses) vit dans Santé et Entraînement.
                    VStack(spacing: 12) {
                        SyncStatusBadge()
                        SetupChecklistCard { showSettings = true }
                        RingsCoachingCard(snapshot: snapshot)
                        TodayChecklistCard(snapshot: snapshot) { addingFood = true }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    // Le lundi (ou à la première ouverture de la semaine), la semaine en cours est figée.
                    .task(id: snapshot.plan.currentWeek.map { FrozenWeek.dayKey($0.start) }) {
                        if WeekFreezer.update(plan: snapshot.plan, context: context) { app.dataVersion += 1 }
                    }
                }
            }
            .background(AppBackground())
            .navigationTitle("Aujourd'hui, \(today.formatted(.dateTime.day().month(.abbreviated)))")
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $addingFood) { AddFoodView { app.dataVersion += 1 } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .refreshable {
                try? await sync.syncSleepData(force: true)
                await app.syncAll(context: context, profile: profiles.first)
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { today = .now }
            }
            .task(id: Calendar.current.startOfDay(for: today)) {
                // Attend le prochain minuit, puis met le titre à jour.
                let calendar = Calendar.current
                guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) else { return }
                try? await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSinceNow + 1)))
                if !Task.isCancelled { today = .now }
            }
        }
    }
}

/// Carte principale façon Bevel : effort, récupération, sommeil en anneaux, puis le coaching du jour.
private struct RingsCoachingCard: View {
    let snapshot: CoachSnapshot

    var body: some View {
        let brief = snapshot.brief
        VStack(alignment: .leading, spacing: 16) {
            // Héros façon Whoop : la récupération en grand, colorée selon sa zone ; effort et sommeil autour (Bevel).
            HStack(alignment: .top, spacing: 4) {
                NavigationLink {
                    EffortDetailView(today: snapshot.effortToday, target: snapshot.effortTarget, history: snapshot.effortHistory,
                                     verdict: brief.adapted.isEmpty ? .rest : brief.verdict)
                } label: {
                    SideRing(title: "Effort", fraction: snapshot.effortToday / 21,
                             text: snapshot.effortToday < 0.05 ? "0" : snapshot.effortToday.oneDecimal,
                             suffix: "cible \(snapshot.effortTarget.lowerBound.noDecimal)–\(snapshot.effortTarget.upperBound.noDecimal)",
                             colors: Theme.strainGradient)
                }
                NavigationLink {
                    ReadinessDetailView(readiness: snapshot.readiness, history: Array(snapshot.readinessHistory.suffix(30)),
                                        hrvSource: snapshot.hrvSource)
                } label: {
                    // Même taille que les deux autres ; couleur selon la zone (vert / blé / brique).
                    SideRing(title: "Récupération", fraction: Double(snapshot.readiness?.score ?? 0) / 100,
                             text: snapshot.readiness.map { "\($0.score)" } ?? "–",
                             suffix: snapshot.readiness == nil ? "calibrage" : "/100",
                             colors: snapshot.readiness.map { [Theme.color(for: $0.level).opacity(0.5), Theme.color(for: $0.level)] }
                                ?? Theme.recoveryGradient)
                }
                NavigationLink {
                    SleepDetailView(snapshot: snapshot)
                } label: {
                    SideRing(title: "Sommeil", fraction: Double(snapshot.lastSleepScore?.score ?? 0) / 100,
                             text: snapshot.lastSleepScore.map { "\($0.score)" } ?? "–", suffix: "score",
                             colors: Theme.sleepGradient)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Divider()

            NavigationLink {
                DailyBriefDetailView(brief: brief, confidence: snapshot.confidence)
            } label: {
                let summary = CoachSummary.make(snapshot)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CapsLabel("Coach du jour")
                        Spacer()
                        StatusPill(text: summary.pill, symbol: summary.pillSymbol,
                                   color: summary.pill == "Séance faite" ? Theme.good : (summary.isRestDay ? Theme.sleep : brief.verdict.color))
                        DetailChevron()
                    }
                    Text(summary.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Séance du jour : la muscu se lance d'ici, en un tap.
            let sessions = brief.adapted.filter { $0.kind != .rest }
            if !sessions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sessions) { session in
                        HStack(spacing: 10) {
                            SessionRow(session: session, changed: !brief.planned.contains(session), compact: true)
                            Spacer(minLength: 4)
                            if session.kind.isStrength {
                                RoutineStartMenu()
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.well.opacity(0.6), in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    if snapshot.weekPlan.map({ !$0.pendingToday.isEmpty }) ?? false {
                        NavigationLink { WeekPlannerView() } label: {
                            Label("Pas aujourd'hui ? Changer de jour", systemImage: "calendar.badge.clock")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .scrollAppear()
    }
}

/// Anneau latéral compact, libellé en capitales sous l'anneau.
private struct SideRing: View {
    let title: String
    let fraction: Double
    let text: String
    let suffix: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                GradientRing(fraction: fraction, colors: colors, lineWidth: 9)
                VStack(spacing: 0) {
                    Text(text).font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit()
                    Text(suffix).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
            }
            .frame(width: 96, height: 96)
            CapsLabel(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        // Lu d'un bloc par VoiceOver : « Récupération, 72 /100 ».
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(text) \(suffix)")
    }
}
