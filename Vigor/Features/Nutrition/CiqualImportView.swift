import SwiftUI
import UniformTypeIdentifiers

/// Table CIQUAL (ANSES) : la version 2025 est intégrée à l'app ; une version plus récente peut être importée.
struct CiqualImportView: View {
    @Environment(\.dismiss) private var dismiss
    var isSheet = false
    @State private var store = CiqualStore.shared
    @State private var importing = false
    @State private var confirmRemove = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: store.isInstalled ? "checkmark.seal.fill" : "leaf.fill")
                        .font(.title2)
                        .foregroundStyle(store.isInstalled ? Theme.good : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.isInstalled ? "\(store.foods.count) aliments génériques" : "Table CIQUAL non installée")
                            .font(.headline)
                        if let date = store.installedAt {
                            Text("\(store.versionLabel) le \(date.formatted(date: .abbreviated, time: .omitted)) · fonctionne hors ligne")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if store.isInstalled {
                            Text("\(store.versionLabel) · fonctionne hors ligne")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Riz cuit, blanc de poulet, lentilles, banane… les aliments sans code-barres, au gramme près.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if store.isWorking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(store.progress).font(.subheadline)
                    }
                }
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.alert)
                }
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("Importer une version plus récente", systemImage: "folder.fill")
                }
                .disabled(store.isWorking)
            } header: {
                Text("Mise à jour")
            } footer: {
                Text("""
                Rien à faire pour l'instant : la table CIQUAL 2025 est déjà dans l'app. Quand l'ANSES publiera une nouvelle version (ciqual.anses.fr → Téléchargement), enregistre le fichier Excel .xlsx dans Fichiers et importe-le ici. L'archive XML .zip marche aussi ; les formats .xls (ancien Excel) et .7z ne sont pas lisibles sur iPhone.
                """)
            }

            if store.hasImportedTable {
                Section {
                    Button("Revenir à la table intégrée", role: .destructive) { confirmRemove = true }
                        .confirmationDialog("Revenir à la table intégrée ?", isPresented: $confirmRemove, titleVisibility: .visible) {
                            Button("Revenir à CIQUAL 2025", role: .destructive) { store.remove() }
                            Button("Annuler", role: .cancel) {}
                        } message: {
                            Text("La table importée est supprimée. Les aliments déjà ajoutés à ton journal sont conservés.")
                        }
                }
            }

            Section {
            } footer: {
                Text("Table de composition nutritionnelle des aliments CIQUAL, ANSES. Licence ouverte Etalab. Valeurs pour 100 g ; « traces » compte pour 0 et « < x » pour la moitié du seuil.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Aliments génériques")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.spreadsheet, .zip, .xml, .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await store.importFiles(urls) }
            }
        }
    }
}
