import SwiftUI
import SwiftData

/// « À faire aujourd'hui » : ce qu'il reste à faire, avec l'action à portée de pouce.
struct TodayChecklistCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    let snapshot: CoachSnapshot
    let onAddFood: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                CapsLabel("À faire aujourd'hui").padding(.bottom, 6)
                mealRow
                // La séance du jour vit dans la carte coaching ; ici, seulement la coche une fois faite.
                if let today = snapshot.weekStatus.first(where: { Calendar.current.isDateInToday($0.date) }),
                   today.status == .done || today.status == .partial {
                    Divider().padding(.leading, 44)
                    ChecklistRow(symbol: "checkmark", title: today.status == .done ? "Séance faite" : "Séance en partie faite",
                                 subtitle: today.done.joined(separator: " + "), done: true)
                }
                Divider().padding(.leading, 44)
                NavigationLink {
                    SleepNeedDetailView(need: snapshot.sleepNeed, performance: snapshot.lastSleepPerformance,
                                        lastNight: snapshot.wellness.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0.sleepHours : nil },
                                        regularity: snapshot.bedtimeRegularity)
                } label: {
                    ChecklistRow(symbol: "moon.zzz.fill", title: "Coucher vers \(snapshot.sleepNeed.bedtimeText)",
                                 subtitle: "Besoin de \(snapshot.sleepNeed.total.hoursText) cette nuit", done: false) {
                        DetailChevron()
                    }
                }
                .buttonStyle(.plain)
                if let report = snapshot.weeklyReport, let review = snapshot.weeklyReview,
                   [1, 2].contains(Calendar.current.component(.weekday, from: .now)) {
                    Divider().padding(.leading, 44)
                    NavigationLink {
                        DetailPage(title: "Revue de la semaine") { WeeklyReviewCard(report: report, review: review) }
                    } label: {
                        ChecklistRow(symbol: "calendar.badge.checkmark", title: "Revue de la semaine",
                                     subtitle: review.strongPoint, done: false) { DetailChevron() }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var mealRow: some View {
        if let targets = snapshot.macroTargets {
            let today = snapshot.todayNutrition
            let kcalLeft = max(0, targets.kcal - today.kcal)
            let proteinLeft = max(0, targets.protein - today.protein)
            let done = today.kcal >= targets.kcal * 0.9 && today.protein >= targets.protein * 0.9
            ChecklistRow(symbol: "fork.knife", title: done ? "Objectifs nutrition atteints" : "Manger",
                         subtitle: done ? "\(today.kcal.noDecimal) kcal · \(today.protein.noDecimal) g de protéines"
                                        : "Encore \(kcalLeft.noDecimal) kcal · \(proteinLeft.noDecimal) g de protéines",
                         done: done) {
                addButton("Repas", action: onAddFood)
            }
        } else {
            ChecklistRow(symbol: "fork.knife", title: "Manger", subtitle: "Note tes repas pour suivre tes apports", done: false) {
                addButton("Repas", action: onAddFood)
            }
        }
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus").font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(Theme.accent)
        .controlSize(.regular)
        .frame(minHeight: 44)
    }
}

/// Ligne de liste : pastille (cochée si fait), titre, détail, action à droite.
struct ChecklistRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    let done: Bool
    private let trailing: Trailing

    init(symbol: String, title: String, subtitle: String, done: Bool, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.done = done
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark" : symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(done ? Color.white : Theme.accent)
                .frame(width: 32, height: 32)
                .background(done ? AnyShapeStyle(Theme.good) : AnyShapeStyle(Theme.well), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

extension ChecklistRow where Trailing == EmptyView {
    init(symbol: String, title: String, subtitle: String, done: Bool) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, done: done) { EmptyView() }
    }
}

/// Démarrage guidé : ce qu'il reste à configurer pour que Vigor soit fiable. Disparaît une fois complet.
struct SetupChecklistCard: View {
    @Environment(AppModel.self) private var app
    @Environment(SyncService.self) private var sync
    @Query private var profiles: [AthleteProfile]
    @Query private var routines: [WorkoutRoutine]
    @AppStorage("setup.dismissed") private var dismissed = false
    let onOpenSettings: () -> Void

    private struct Step: Identifiable {
        var id: String { title }
        let title: String
        let done: Bool
    }

    var body: some View {
        let steps = makeSteps()
        let remaining = steps.filter { !$0.done }.count
        if remaining > 0 && !dismissed {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CapsLabel("Configurer Vigor")
                        Spacer()
                        Text("\(steps.count - remaining) / \(steps.count)").font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(steps) { step in
                        HStack(spacing: 10) {
                            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.done ? Theme.good : Color.secondary)
                            Text(step.title).font(.subheadline)
                                .foregroundStyle(step.done ? Color.secondary : Color.primary)
                        }
                    }
                    HStack {
                        Button("Compléter", action: onOpenSettings)
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accent)
                        Spacer()
                        Button("Masquer") { dismissed = true }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func makeSteps() -> [Step] {
        let profile = profiles.first
        return [
            Step(title: "Objectif et date de course", done: !(profile?.raceName.isEmpty ?? true)),
            Step(title: "Taille et poids", done: (profile?.heightCm ?? 0) > 0 && (profile?.weightKg ?? 0) > 0),
            Step(title: "FTP (même approximative)", done: (profile?.ftp ?? 0) > 0),
            Step(title: "Apple Santé synchronisée", done: sync.lastSyncDate != nil || app.lastSync > .distantPast),
            Step(title: "Garmin via Intervals.icu", done: !app.intervalsAPIKey.isEmpty),
            Step(title: "Programme de muscu (Sport → Musculation)", done: !routines.isEmpty)
        ]
    }
}
