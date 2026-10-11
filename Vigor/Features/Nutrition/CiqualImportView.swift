import SwiftUI
import UniformTypeIdentifiers

/// Installation de la table CIQUAL (ANSES) : téléchargement direct ou import du fichier officiel.
struct CiqualImportView: View {
    @Environment(\.dismiss) private var dismiss
    var isSheet = false
    @State private var store = CiqualStore.shared
    @State private var address = CiqualStore.defaultURLs.first ?? ""
    @State private var importing = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: store.isInstalled ? "checkmark.seal.fill" : "leaf.fill")
                        .font(.title2)
                        .foregroundStyle(store.isInstalled ? Theme.good : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.isInstalled ? "\(store.foods.count) aliments génériques installés" : "Table CIQUAL non installée")
                            .font(.headline)
                        if let date = store.installedAt {
                            Text("Installée le \(date.formatted(date: .abbreviated, time: .omitted)) · fonctionne hors ligne")
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
                    Task { await store.download(from: address) }
                } label: {
                    Label(store.isInstalled ? "Mettre à jour depuis l'ANSES" : "Télécharger depuis l'ANSES", systemImage: "arrow.down.circle.fill")
                }
                .disabled(store.isWorking)
                TextField("Adresse de l'archive XML", text: $address, axis: .vertical)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("1. Téléchargement direct")
            } footer: {
                Text("Si l'ANSES a changé l'adresse du fichier, utilise l'import ci-dessous.")
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("Importer le fichier (.zip ou .xml)", systemImage: "folder.fill")
                }
                .disabled(store.isWorking)
            } header: {
                Text("2. Ou import manuel")
            } footer: {
                Text("""
                Dans Safari : ciqual.anses.fr → « Téléchargement » → table complète au format XML. Enregistre l'archive dans Fichiers, puis importe-la ici (l'archive .zip telle quelle, ou les fichiers alim, compo et const extraits).
                """)
            }

            if store.isInstalled {
                Section {
                    Button("Supprimer la table", role: .destructive) { store.remove() }
                } footer: {
                    Text("Table de composition nutritionnelle des aliments CIQUAL, ANSES. Licence ouverte Etalab. Valeurs pour 100 g ; « traces » compte pour 0 et « < x » pour la moitié du seuil.")
                }
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
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .xml, .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await store.importFiles(urls) }
            }
        }
    }
}
