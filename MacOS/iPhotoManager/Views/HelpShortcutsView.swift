import SwiftUI
import AppKit

/// Full de dreceres i gestos (⌘/). Contingut estàtic; l'ajuda completa viu a
/// la guia web de miratfotos.com (una sola font per a Mac i Windows).
struct HelpShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    static let guideURL = "https://miratfotos.com/ajuda/photo-manager"

    private struct Item: Identifiable {
        let id = UUID()
        let keys: String
        let text: String
    }

    private let general: [Item] = [
        Item(keys: "⌘O", text: "Afegir una carpeta (se suma a les obertes)"),
        Item(keys: "⌘A / ⌘D", text: "Seleccionar-ho tot / desseleccionar"),
        Item(keys: "⌘Z", text: "Desfer l'últim esborrat"),
        Item(keys: "Tab", text: "Canviar visor lateral ↔ superposat"),
        Item(keys: "Supr", text: "Eliminar la selecció (a la Paperera)"),
        Item(keys: "Esc", text: "Sortir del mode dispositiu"),
        Item(keys: "⌘/", text: "Aquest full d'ajuda"),
    ]

    private let viewer: [Item] = [
        Item(keys: "← →", text: "Foto anterior / següent"),
        Item(keys: "+ − 0", text: "Apropar · allunyar · zoom 100%"),
        Item(keys: "F", text: "Ajustar a la pantalla"),
        Item(keys: "C", text: "Copiar la foto al destí (o pujar-la a Mirat)"),
        Item(keys: "Espai", text: "Reproduir / pausar el vídeo"),
        Item(keys: "Esc", text: "Tancar el visor"),
    ]

    private let mouse: [Item] = [
        Item(keys: "clic", text: "Obre la foto al visor"),
        Item(keys: "⌘/⇧+clic", text: "Selecció individual / per interval (al requadre)"),
        Item(keys: "arrossegar", text: "En zona buida: selecció per rectangle"),
        Item(keys: "arrossegar", text: "Una miniatura cap al Finder o Mail: copia els fitxers"),
        Item(keys: "roda", text: "Al visor: zoom centrat al cursor"),
        Item(keys: "arrossegar", text: "Al visor amb zoom: moure's per la foto"),
        Item(keys: "doble clic", text: "Tanca el visor superposat"),
    ]

    private let tips: [String] = [
        "Amb un destí Mirat actiu, «Copiar» i «Moure» pugen les fotos a Mirat («Moure» esborra el local després de pujar).",
        "Les carpetes s'acumulen: gestiona-les (treure, subcarpetes) clicant la píndola «N carpetes» de dalt.",
        "Del dispositiu: desbloqueja l'iPhone i prem «Confiar» abans de detectar-lo.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Dreceres i gestos")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textDim)
                }
                .buttonStyle(.plain)
                .help("Tancar (Esc)")
            }
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    section("General", items: general)
                    section("Visor", items: viewer)
                }
                VStack(alignment: .leading, spacing: 18) {
                    section("Ratolí i gestos", items: mouse)
                    tipsSection
                }
            }

            Divider()
                .padding(.vertical, 12)

            HStack(spacing: 6) {
                Image(systemName: "book")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                Text("Guia completa (importar, Mirat, duplicats, problemes):")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                Button {
                    if let url = URL(string: Self.guideURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("miratfotos.com/ajuda/photo-manager")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accent)
                        .underline()
                }
                .buttonStyle(.plain)
                .help("Obre la guia al navegador")
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(Color.bgBase)
    }

    private func section(_ title: String, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accent)
                .kerning(0.8)
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.keys)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .frame(width: 86, alignment: .leading)
                    Text(item.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BO DE SABER")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accent)
                .kerning(0.8)
            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("·")
                        .foregroundStyle(Color.accent)
                    Text(tip)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
