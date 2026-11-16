import SwiftUI

/// La conversation avec le juge. On y colle un lien, on explique, on plaide ;
/// le juge tranche.
struct DemanderView: View {

    @Environment(AppModel.self) private var modele
    @State private var saisie = ""
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { defilement in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if modele.echanges.isEmpty {
                            Text("Colle le lien d'une vidéo, d'une liste ou d'une chaîne, ou demande au juge de chercher : « trouve-moi des conférences sur… »")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40)
                        }
                        ForEach(modele.echanges) { echange in
                            Bulle(echange: echange).id(echange.id)
                        }
                        if modele.enAttente {
                            ProgressView().padding().id("attente")
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: modele.echanges.count) {
                    guard let dernier = modele.echanges.last?.id else { return }
                    withAnimation { defilement.scrollTo(dernier, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { barreSaisie }
            .navigationTitle("Demander")
            .toolbar {
                Button("Nouvelle", systemImage: "square.and.pencil") {
                    modele.nouvelleConversation()
                }
                .disabled(modele.echanges.isEmpty || modele.enAttente)
            }
        }
    }

    private var barreSaisie: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Lien, message ou recherche", text: $saisie, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($focus)
            Button {
                let texte = saisie
                saisie = ""
                Task { await modele.demander(texte) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(saisie.trimmingCharacters(in: .whitespaces).isEmpty || modele.enAttente)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct Bulle: View {

    @Environment(AppModel.self) private var modele
    let echange: Echange

    var body: some View {
        HStack {
            if echange.auteur == .moi { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if let etiquette {
                    Label(etiquette.texte, systemImage: etiquette.icone)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(etiquette.couleur)
                }
                Text(echange.texte)
                ForEach(echange.propositions ?? [], id: \.url) { proposition in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(proposition.titre).font(.subheadline.weight(.semibold))
                        Text(proposition.pourquoi).font(.caption).foregroundStyle(.secondary)
                        // Examiner soumet le lien comme s'il avait ete colle :
                        // l'appli lit la page, puis le juge tranche sur pieces.
                        Button("Examiner") {
                            Task { await modele.demander("Examine : \(proposition.url)") }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(modele.enAttente)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(10)
            .background(fond, in: RoundedRectangle(cornerRadius: 14))
            if echange.auteur != .moi { Spacer(minLength: 40) }
        }
    }

    private var fond: Color {
        switch echange.auteur {
        case .moi: Color.accentColor.opacity(0.18)
        case .juge: Color(.secondarySystemBackground)
        case .systeme: Color.orange.opacity(0.15)
        }
    }

    private var etiquette: (texte: String, icone: String, couleur: Color)? {
        switch echange.verdict {
        case .approuveVideo: ("Vidéo approuvée", "checkmark.circle.fill", Color.green)
        case .approuveChaine: ("Chaîne approuvée", "checkmark.seal.fill", Color.green)
        case .approuveListe: ("Liste approuvée", "list.bullet.rectangle.fill", Color.green)
        case .refuse: ("Refusé", "xmark.circle.fill", Color.red)
        case .discussion, nil: nil
        }
    }
}
