import SwiftUI

extension Verdict {
    var color: Color {
        switch self {
        case .push: Theme.strain
        case .go: Theme.recovery
        case .adjust: Theme.nutrition
        case .easy: Theme.sleep
        case .rest: Theme.warning
        }
    }
}

/// Carte d'accueil : ce que tu fais aujourd'hui, adapté à ta nuit, ta récup et ton alimentation.
struct DailyBriefCard: View {
    let brief: DailyBrief

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(brief.verdict.label, systemImage: brief.verdict.symbol)
                        .font(.headline)
                        .foregroundStyle(brief.verdict.color)
                    Spacer()
                }
                EnergyGauge(value: brief.capacity, color: brief.verdict.color, label: "Énergie du jour")
                    .frame(maxWidth: 200)
                    .frame(maxWidth: .infinity)
                Text(brief.headline).font(.subheadline).lineLimit(3)

                ForEach(brief.adapted) { session in
                    SessionRow(session: session, changed: !brief.planned.contains(session), compact: true)
                }

                HStack {
                    Spacer()
                    Text("Voir pourquoi").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    DetailChevron()
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionPrescription
    var changed = false
    /// Compact : titre seul (accueil). Sinon : titre + détail (watts, séries…).
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: session.kind.symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(changed ? Theme.nutrition : .primary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.title).font(.subheadline.weight(.semibold))
                    if changed {
                        Text("adaptée").font(.caption2.weight(.bold)).foregroundStyle(Theme.nutrition)
                    }
                }
                if !compact && !session.detail.isEmpty {
                    Text(session.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Le détail du raisonnement : chaque facteur, son poids, et ce qui a changé.
struct DailyBriefDetailView: View {
    let brief: DailyBrief
    var confidence: DataConfidence?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(brief.verdict.label, systemImage: brief.verdict.symbol)
                            .font(.title3.weight(.semibold)).foregroundStyle(brief.verdict.color)
                        Text(brief.headline).font(.subheadline)
                        EnergyGauge(value: brief.capacity, color: brief.verdict.color, label: "de ta forme habituelle")
                            .frame(maxWidth: 260)
                            .frame(maxWidth: .infinity)
                    }
                }

                if let confidence {
                    GlassCard { ConfidenceRow(confidence: confidence) }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Règles déclenchées", symbol: "list.number")
                        if !brief.redSignals.isEmpty {
                            Text("Signaux rouges : " + brief.redSignals.joined(separator: " · ")).font(.footnote.weight(.semibold))
                        } else {
                            Text("Aucun signal rouge.").font(.footnote)
                        }
                        ForEach(Array(brief.rules.enumerated()), id: \.offset) { index, rule in
                            Text("\(index + 1). \(rule)").font(.footnote.monospacedDigit())
                        }
                        Text("Règle générale : 2 signaux rouges (VFC, sommeil, ratio de charge, fatigue, respiration) → séance adaptée ; 3 signaux ou une douleur déclarée → repos.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if !brief.priorities.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(title: "Priorités du jour", symbol: "checklist")
                            ForEach(Array(brief.priorities.enumerated()), id: \.offset) { index, priority in
                                Text("\(index + 1). \(priority)").font(.footnote)
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Pourquoi : ce que j'ai croisé", symbol: "point.3.connected.trianglepath.dotted")
                        if brief.factors.isEmpty {
                            Text("Pas encore assez de données (sommeil, VFC, séances, repas).").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(FactorDomain.allCases, id: \.self) { domain in
                            let items = brief.factors.filter { $0.domain == domain }
                            if !items.isEmpty {
                                Label(domain.label, systemImage: domain.symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(items) { factor in FactorRow(factor: factor) }
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "Prévu", symbol: "calendar")
                        ForEach(brief.planned) { SessionRow(session: $0) }
                        Divider()
                        SectionTitle(title: "Ce que je te propose", symbol: "wand.and.stars")
                        ForEach(brief.adapted) { session in
                            SessionRow(session: session, changed: !brief.planned.contains(session))
                        }
                        if !brief.changes.isEmpty {
                            Divider()
                            ForEach(brief.changes, id: \.self) { Text("• \($0)").font(.footnote) }
                        }
                    }
                }

                if !brief.fueling.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(title: "Nutrition autour de la séance", symbol: "fork.knife")
                            ForEach(brief.fueling, id: \.self) { Text("• \($0)").font(.footnote) }
                        }
                    }
                }

                ExplanationCard(title: "Comment je décide", symbol: "function", text: """
                Je pars de ta séance prévue (plan Traka ou calendrier Intervals.icu), puis j'estime ta capacité du jour en additionnant l'effet de chaque facteur :
                • Santé : score de récupération (VFC, FC repos, sommeil), nuit dernière, dette de sommeil.
                • Entraînement : fatigue accumulée (forme), pic de charge, séance Legs récente, blessures.
                • Nutrition : calories, glucides et protéines de la veille, rapportés à ta dépense et à ton poids.
                ≥ 100 % et récup au vert : jour pour performer · 85–100 % : plan suivi · 65–85 % : séance ajustée · 45–65 % : endurance facile · < 45 % : repos.
                Une nuit de moins de 6 h ou une fatigue extrême suppriment l'intensité quel que soit le score : c'est là que le risque dépasse le bénéfice.
                """)
                ReferencesCard(references: brief.references)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Plan du jour")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FactorRow: View {
    let factor: CoachFactor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: factor.impact < 0 ? "arrow.down.circle.fill" : (factor.impact > 0 ? "arrow.up.circle.fill" : "minus.circle.fill"))
                .foregroundStyle(factor.impact < -0.1 ? Theme.warning : (factor.impact < 0 ? Theme.nutrition : Theme.recovery))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(factor.name).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(factor.impact == 0 ? "neutre" : String(format: "%+.0f %%", factor.impact * 100))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(factor.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
