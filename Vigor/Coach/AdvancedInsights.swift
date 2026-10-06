import Foundation

struct RatedSession: Equatable {
    let date: Date
    let rpe: Int
    let intensityFactor: Double?
}

struct EnduranceQuality: Equatable {
    let date: Date
    let durationSeconds: Double
    let zoneSeconds: [Double]
    let decoupling: Double?
}

/// Règles qui exploitent les nouvelles données : discipline, volume, hors sport, RPE, horaires,
/// zones de FC, dérive cardiaque, symptômes, chaussures, hydratation.
enum AdvancedInsights {
    static func analyze(disciplineLoads: [DisciplineLoad],
                        volumeAlerts: [String],
                        lifeLoad7: Double,
                        lifeHours7: Double,
                        rated: [RatedSession],
                        bedtimeSD: Double?,
                        averageBedtime: String?,
                        endurance: [EnduranceQuality],
                        symptoms: [SymptomPattern],
                        shoeKm: [(name: String, km: Double)],
                        waterRatio7: Double?,
                        today: Date) -> [Insight] {
        var insights: [Insight] = []

        for load in disciplineLoads where load.name != "Global" {
            if let ratio = load.ratio, ratio > 1.5 {
                insights.append(Insight(id: "discipline.\(load.name)", category: .load, severity: .warning,
                                        title: "Pic de charge en \(load.name.lowercased())",
                                        evidence: [String(format: "Ratio 7 j / 28 j : %.2f (zone sûre ≤ 1,3)", ratio),
                                                   String(format: "%.0f TSS/j cette semaine contre %.0f en moyenne", load.acute, load.chronic)],
                                        recommendation: "Ton corps n'est pas habitué à ce volume dans cette discipline (tendons, articulations). Stabilise la semaine prochaine.",
                                        references: [Science.gabbett2016]))
            }
        }

        if !volumeAlerts.isEmpty {
            insights.append(Insight(id: "volume.increase", category: .load, severity: .watch,
                                    title: "Volume en hausse de plus de 10 %",
                                    evidence: volumeAlerts,
                                    recommendation: "Au-delà d'environ 10 % par semaine, le risque de blessure augmente. Garde le même volume la semaine prochaine.",
                                    references: [Science.gabbett2016]))
        }

        if lifeHours7 >= 3 {
            insights.append(Insight(id: "life.load", category: .load, severity: lifeLoad7 >= 150 ? .watch : .info,
                                    title: "Charge physique hors sport importante",
                                    evidence: [String(format: "%.1f h cette semaine (travaux, journées debout…)", lifeHours7),
                                               String(format: "≈ %.0f TSS ajoutés à ta fatigue", lifeLoad7)],
                                    recommendation: "Ces heures fatiguent autant qu'une séance : elles sont comptées dans ta fatigue, et le coach allège en conséquence.",
                                    references: [Science.foster1998]))
        }

        let cutoff = today.addingTimeInterval(-14 * 86_400)
        let mismatched = rated.filter { $0.date >= cutoff && $0.rpe >= 8 && ($0.intensityFactor ?? 1) < 0.75 }
        if mismatched.count >= 2 {
            insights.append(Insight(id: "rpe.mismatch", category: .recovery, severity: .watch,
                                    title: "Séances faciles ressenties comme dures",
                                    evidence: ["\(mismatched.count) séances à faible intensité notées RPE ≥ 8 sur 14 jours"],
                                    recommendation: "Quand l'effort ressenti dépasse ce que mesurent les capteurs, c'est souvent de la fatigue, un manque de sommeil ou de glucides, la chaleur ou une maladie qui commence. Lève le pied 2 jours.",
                                    references: [Science.foster1998, Science.halson2014]))
        }

        if let sd = bedtimeSD, sd > 60 {
            insights.append(Insight(id: "sleep.bedtime", category: .sleep, severity: .watch,
                                    title: "Horaires de coucher irréguliers",
                                    evidence: [String(format: "Ton heure de coucher varie de ±%.0f min (moyenne : %@)", sd, averageBedtime ?? "–")],
                                    recommendation: "Garde un coucher à ±30 min, même le week-end : la régularité améliore la qualité du sommeil autant que sa durée.",
                                    references: [Science.phillips2017]))
        }

        // Zones de FC sur 28 jours.
        let recentEndurance = endurance.filter { $0.date >= today.addingTimeInterval(-28 * 86_400) && $0.zoneSeconds.count == 5 }
        let zoneTotals = (0..<5).map { index in recentEndurance.reduce(0.0) { $0 + $1.zoneSeconds[index] } }
        let zoneTotal = zoneTotals.reduce(0, +)
        if zoneTotal >= 4 * 3600 {
            let lowShare = (zoneTotals[0] + zoneTotals[1]) / zoneTotal
            let evidence = [String(format: "Z1–Z2 : %.0f %% · Z3 : %.0f %% · Z4–Z5 : %.0f %%", lowShare * 100, zoneTotals[2] / zoneTotal * 100, (zoneTotals[3] + zoneTotals[4]) / zoneTotal * 100),
                            String(format: "%.1f h analysées sur 28 jours", zoneTotal / 3600)]
            if lowShare < 0.7 {
                insights.append(Insight(id: "zones.lowZ2", category: .load, severity: .watch,
                                        title: "Pas assez de temps en zone 2",
                                        evidence: evidence,
                                        recommendation: "L'endurance fondamentale se construit en Z1–Z2 : ralentis tes sorties faciles, quitte à les faire au home trainer pour mieux contrôler.",
                                        references: [Science.seiler2010]))
            } else if lowShare >= 0.78 {
                insights.append(Insight(id: "zones.goodZ2", category: .load, severity: .positive,
                                        title: "Bonne base en zone 2",
                                        evidence: evidence,
                                        recommendation: "Ta répartition construit bien l'endurance fondamentale.",
                                        references: [Science.seiler2010]))
            }
        }

        // Dérive cardiaque sur les sorties longues.
        let long = endurance.filter { $0.durationSeconds >= 90 * 60 && $0.decoupling != nil }.sorted { $0.date < $1.date }
        if let latest = long.last, let drift = latest.decoupling {
            var evidence = [String(format: "Dernière sortie longue : dérive de %.1f %% (repère : < 5 %%)", drift)]
            if long.count >= 4 {
                let older = Stats.mean(long.prefix(long.count / 2).compactMap(\.decoupling)) ?? drift
                let newer = Stats.mean(long.suffix(long.count - long.count / 2).compactMap(\.decoupling)) ?? drift
                evidence.append(String(format: "Moyenne : %.1f %% → %.1f %%", older, newer))
                if newer < older - 1 {
                    insights.append(Insight(id: "drift.improving", category: .load, severity: .positive,
                                            title: "Ton endurance aérobie progresse",
                                            evidence: evidence,
                                            recommendation: "Ta FC dérive moins sur les sorties longues : ton moteur aérobie se renforce. Tu peux allonger la sortie longue.",
                                            references: [Science.allenCoggan]))
                    return finish(insights, symptoms: symptoms, shoeKm: shoeKm, waterRatio7: waterRatio7)
                }
            }
            if drift > 5 {
                insights.append(Insight(id: "drift.high", category: .load, severity: .watch,
                                        title: "Dérive cardiaque élevée sur la sortie longue",
                                        evidence: evidence,
                                        recommendation: "Ta FC monte à puissance égale en fin de sortie : base aérobie encore à construire, ou déshydratation / manque de glucides. Garde la durée, mange et bois plus, reste en Z2.",
                                        references: [Science.allenCoggan, Science.jeukendrup2014]))
            }
        }
        return finish(insights, symptoms: symptoms, shoeKm: shoeKm, waterRatio7: waterRatio7)
    }

    private static func finish(_ base: [Insight], symptoms: [SymptomPattern], shoeKm: [(name: String, km: Double)], waterRatio7: Double?) -> [Insight] {
        var insights = base
        for pattern in symptoms where pattern.isRecurrent {
            var evidence = [String(format: "%d épisodes sur 14 jours (%d au total), intensité moyenne %.1f / 10", pattern.recentCount, pattern.count, pattern.averageIntensity)]
            if let onset = pattern.averageOnset { evidence.append(String(format: "Apparition en moyenne après %.0f min d'effort", onset)) }
            evidence += pattern.findings
            insights.append(Insight(id: "symptom.\(pattern.key)", category: .recovery, severity: .warning,
                                    title: "Symptôme récurrent : \(pattern.key)",
                                    evidence: evidence,
                                    recommendation: "Un symptôme qui revient doit être montré à un professionnel (médecin du sport, kiné, podologue). En attendant, compare les contextes ci-dessus : chaussure, terrain, fatigue.",
                                    references: []))
        }
        for shoe in shoeKm where shoe.km >= 600 {
            insights.append(Insight(id: "shoe.\(shoe.name)", category: .data, severity: .info,
                                    title: "Chaussures usées : \(shoe.name)",
                                    evidence: [String(format: "%.0f km parcourus", shoe.km)],
                                    recommendation: "Au-delà de 600–800 km, l'amorti diminue nettement. Pense à les remplacer, surtout si une douleur apparaît.",
                                    references: []))
        }
        if let ratio = waterRatio7, ratio < 0.7 {
            insights.append(Insight(id: "hydration.low", category: .nutrition, severity: .info,
                                    title: "Hydratation insuffisante",
                                    evidence: [String(format: "%.0f %% de ton objectif d'eau en moyenne sur 7 jours", ratio * 100)],
                                    recommendation: "Garde une gourde à portée de main et bois 500 à 750 ml par heure de sport.",
                                    references: []))
        }
        return insights
    }
}
