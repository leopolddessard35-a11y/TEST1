import SwiftUI

/// Indicateur discret de la synchro du sommeil : en cours, réussie (avec l'heure) ou en erreur (avec « Réessayer »).
struct SyncStatusBadge: View {
    @Environment(SyncService.self) private var sync

    var body: some View {
        HStack(spacing: 6) {
            if sync.isSyncing {
                ProgressView().controlSize(.mini)
                Text("Synchronisation de ta nuit…")
            } else if let error = sync.syncError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text(error.localizedDescription).lineLimit(1)
                Button("Réessayer") {
                    Task { try? await sync.syncSleepData(force: true) }
                }
                .font(.caption2.weight(.semibold))
            } else if let date = sync.lastSyncDate {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.recovery)
                Text(Calendar.current.isDateInToday(date)
                     ? "Nuit synchronisée à \(date.formatted(date: .omitted, time: .shortened))"
                     : "Dernière synchro \(date.formatted(.relative(presentation: .named)))")
                if let source = sync.lastSource { Text("· \(source)").foregroundStyle(.tertiary) }
            } else {
                Image(systemName: "moon.zzz").foregroundStyle(.secondary)
                Text("Nuit pas encore synchronisée")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.2), value: sync.isSyncing)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SyncStatusBadge()
        .environment(SyncService.preview())
        .padding()
}
