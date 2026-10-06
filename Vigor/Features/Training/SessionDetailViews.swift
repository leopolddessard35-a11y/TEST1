import SwiftUI
import SwiftData
import Charts

// MARK: - Séance d'endurance

struct ActivityDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query private var shoes: [Shoe]
    @Bindable var activity: CardioActivity
    let thresholds: Thresholds

    var body: some View {
        let tss = activity.providedTSS ?? TrainingLoad.estimateTSS(
            sport: activity.sport, durationSeconds: activity.durationSeconds,
            normalizedPower: activity.normalizedPower, averagePower: activity.averagePower,
            averageHeartRate: activity.averageHeartRate, rpe: activity.rpe, thresholds: thresholds)
        let intensity = activity.providedIntensity ?? TrainingLoad.intensityFactor(
            sport: activity.sport, normalizedPower: activity.normalizedPower, averagePower: activity.averagePower,
            averageHeartRate: activity.averageHeartRate, thresholds: thresholds)

        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Durée", value: (activity.durationSeconds / 3600).hoursText)
                    StatTile(title: "Distance", value: activity.distanceMeters.map { String(format: "%.1f km", $0 / 1000) } ?? "–")
                    StatTile(title: "Charge", value: "\(tss.noDecimal) TSS")
                    StatTile(title: "Puissance", value: activity.averagePower.map { "\($0.noDecimal) W" } ?? "–",
                             caption: activity.normalizedPower.map { "NP \($0.noDecimal) W" } ?? "")
                    StatTile(title: "FC moyenne", value: activity.averageHeartRate.map { "\($0.noDecimal) bpm" } ?? "–")
                    StatTile(title: "Intensité", value: intensity.map { String(format: "IF %.2f", $0) } ?? "–")
                    StatTile(title: "Cadence", value: activity.averageCadence.map { $0.noDecimal } ?? "–",
                             caption: activity.sport == .running ? "pas/min" : "tr/min")
                    StatTile(title: "Dénivelé +", value: activity.elevationGain.map { "\($0.noDecimal) m" } ?? "–")
                    StatTile(title: "Dérive cardiaque", value: activity.decouplingPercent.map { String(format: "%.1f %%", $0) } ?? "–",
                             caption: "repère : < 5 %")
                }

                if activity.sport == .running, let meters = activity.distanceMeters, meters > 0 {
                    let pace = activity.durationSeconds / (meters / 1000)
                    let climb = (activity.elevationGain ?? 0) / (meters / 1000)
                    // Allure ajustée au dénivelé (approximation : ~6 s/km gagnées par 10 m D+/km).
                    let gap = max(0, pace - climb * 0.6)
                    GlassCard {
                        HStack {
                            StatTile(title: "Allure", value: Self.pace(pace))
                            StatTile(title: "Allure ajustée (GAP)", value: Self.pace(gap), caption: "estimée via le D+")
                        }
                    }
                }

                zonesCard

                if let drift = activity.decouplingPercent {
                    ExplanationCard(title: "Dérive cardiaque", symbol: "heart.text.square", text: drift < 5
                        ? String(format: "%.1f %% : ta FC reste stable sur la durée. Ton endurance aérobie est solide à cette intensité.", drift)
                        : String(format: "%.1f %% : ta FC monte en fin de séance à effort égal. Base aérobie à consolider, ou hydratation / glucides insuffisants. C'est le meilleur indicateur de progression sans chrono : il doit baisser au fil des semaines.", drift))
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Effort ressenti (RPE)", symbol: "gauge.with.dots.needle.67percent")
                        RPEPicker(value: activity.rpe) { value in
                            activity.rpe = value
                            save()
                        }
                        Text("Il corrige les capteurs : une séance facile ressentie comme dure est un signal de fatigue.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Contexte", symbol: "map")
                        Picker("Terrain", selection: Binding(get: { activity.terrainRaw ?? "" }, set: { activity.terrainRaw = $0.isEmpty ? nil : $0; save() })) {
                            Text("Non précisé").tag("")
                            ForEach(Terrain.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        if activity.sport == .running {
                            Picker("Chaussures", selection: Binding(get: { activity.shoeID ?? "" }, set: { activity.shoeID = $0.isEmpty ? nil : $0; save() })) {
                                Text("Par défaut").tag("")
                                ForEach(shoes.filter { !$0.retired }) { Text($0.name).tag($0.shoeID) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var zonesCard: some View {
        let total = activity.zoneSeconds.reduce(0, +)
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Temps par zone de FC", symbol: "chart.bar.fill")
                if activity.zoneSeconds.count == 5, total > 0 {
                    ForEach(0..<5, id: \.self) { index in
                        let seconds = activity.zoneSeconds[index]
                        HStack {
                            Text(HeartRateZones.labels[index]).font(.caption).frame(width: 96, alignment: .leading)
                            AnimatedBar(fraction: seconds / total, color: Self.zoneColor(index), height: 12)
                            Text("\((seconds / 3600).hoursText)").font(.caption.monospacedDigit()).frame(width: 60, alignment: .trailing)
                        }
                    }
                    let low = (activity.zoneSeconds[0] + activity.zoneSeconds[1]) / total
                    Text(String(format: "%.0f %% en Z1–Z2 (endurance fondamentale)", low * 100)).font(.footnote.weight(.semibold))
                } else {
                    Text("Zones indisponibles : renseigne ta FC seuil ou ta FC max dans Réglages, puis resynchronise.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func save() {
        try? context.save()
        app.dataVersion += 1
    }

    static func zoneColor(_ index: Int) -> Color {
        [Theme.sleep, Theme.recovery, Theme.nutrition, Theme.strain, Theme.warning][min(max(index, 0), 4)]
    }

    static func pace(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }
}

// MARK: - Exercice de musculation

struct ExerciseDetailView: View {
    let exercise: String
    let sessions: [ExerciseSession]

    var body: some View {
        let ordered = sessions.filter { !$0.workingSets.isEmpty }.sorted { $0.date < $1.date }
        let best = ordered.max { $0.bestEstimated1RM < $1.bestEstimated1RM }
        let heaviest = ordered.max { $0.topWeight < $1.topWeight }
        let targets = MuscleMap.targets(for: exercise)

        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "1RM estimé (record)", value: best.map { "\($0.bestEstimated1RM.oneDecimal) kg" } ?? "–",
                             caption: best.map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "")
                    StatTile(title: "Charge max", value: heaviest.map { "\($0.topWeight.oneDecimal) kg" } ?? "–",
                             caption: heaviest.map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "")
                    StatTile(title: "Séances", value: "\(ordered.count)")
                    StatTile(title: "Muscles", value: targets.primary.first?.label ?? "–",
                             caption: targets.secondary.map(\.label).joined(separator: ", "))
                }

                if ordered.count >= 2 {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "1RM estimé dans le temps", symbol: "chart.line.uptrend.xyaxis")
                            Chart(ordered, id: \.date) { session in
                                LineMark(x: .value("Date", session.date), y: .value("1RM", session.bestEstimated1RM))
                                    .foregroundStyle(Theme.strain)
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("Date", session.date), y: .value("1RM", session.bestEstimated1RM))
                                    .foregroundStyle(Theme.strain)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 180)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Historique", symbol: "list.bullet")
                        ForEach(ordered.reversed(), id: \.date) { session in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(session.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                                    if session.date == best?.date {
                                        Label("Record", systemImage: "trophy.fill").font(.caption2.weight(.bold)).foregroundStyle(Theme.nutrition)
                                    }
                                    Spacer()
                                    Text("1RM \(session.bestEstimated1RM.oneDecimal) kg").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(session.workingSets.map { set -> String in
                                    let reps = set.reps.map(String.init) ?? "–"
                                    let rir = set.rpe.map { " · RIR \(max(0, Int((10 - $0).rounded())))" } ?? ""
                                    return "\(set.weightKg?.oneDecimal ?? "–") kg × \(reps)\(rir)"
                                }.joined(separator: "   "))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ExplanationCard(title: "Comment lire", symbol: "lightbulb", text: "1RM estimé = charge × (1 + reps / 30) sur ta meilleure série. RIR = répétitions en réserve (10 − RPE) : vise 1 à 3 en prise de masse. Si le 1RM stagne 4 séances, le coach le signale et propose une décharge.")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle(exercise)
        .navigationBarTitleDisplayMode(.inline)
    }
}
