import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        TabView {
            SummaryLibraryView()
                .tabItem { Label("Resúmenes", systemImage: "doc.text") }
                .badge(model.unreadVideoCount)

            FavoritesLibraryView()
                .tabItem { Label("Favoritos", systemImage: "star.fill") }
                .badge(model.favoriteHistory.count)

            TextSummaryLibraryView()
                .tabItem { Label("Texto/OCR", systemImage: "text.viewfinder") }
                .badge(model.unreadTextCount)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
    }
}

private struct SummaryLibraryView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(model.history) { record in
                    NavigationLink(value: record) {
                        SummaryRow(record: record)
                    }
                    .listRowBackground(
                        model.isVideoSummaryRead(record) ? Color.clear : Color.blue.opacity(0.12)
                    )
                    .swipeActions {
                        Button(role: .destructive) {
                            model.deleteSummary(record)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                        Button {
                            model.toggleFavorite(record)
                        } label: {
                            Label(
                                model.isFavorite(record) ? "Quitar favorito" : "Favorito",
                                systemImage: model.isFavorite(record) ? "star.slash" : "star"
                            )
                        }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        Button {
                            model.toggleFavorite(record)
                        } label: {
                            Label(
                                model.isFavorite(record) ? "Quitar de favoritos" : "Añadir a favoritos",
                                systemImage: model.isFavorite(record) ? "star.slash" : "star"
                            )
                        }
                        Button(role: .destructive) {
                            model.deleteSummary(record)
                        } label: {
                            Label("Borrar resumen", systemImage: "trash")
                        }
                        Button {
                            model.discardSummary(record)
                        } label: {
                            Label("Descartar y volver a resumir", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                .onDelete(perform: model.deleteSummaries)
            }
            .navigationTitle("Resúmenes")
            .toolbar {
                ToolbarItem(placement: refreshPlacement) {
                    Button {
                        Task { await model.processNewVideos() }
                    } label: {
                        Label("Buscar vídeos nuevos", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isProcessing)
                }

                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                #endif
            }
            .overlay {
                if model.history.isEmpty {
                    ContentUnavailableView(
                        "Aún no hay resúmenes",
                        systemImage: "play.rectangle.on.rectangle",
                        description: Text("Configura la app y busca vídeos nuevos.")
                    )
                }
            }
            .navigationDestination(for: SummaryRecord.self) { record in
                SummaryDetailView(record: record)
            }
        } detail: {
            ContentUnavailableView(
                "Selecciona un resumen",
                systemImage: "doc.text.magnifyingglass"
            )
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                if model.isProcessing { ProgressView().controlSize(.small) }
                Text(model.status).font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .alert("VideoResume", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var refreshPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }
}

private struct FavoritesLibraryView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(model.favoriteHistory) { record in
                    NavigationLink(value: record) {
                        SummaryRow(record: record)
                    }
                    .listRowBackground(
                        model.isVideoSummaryRead(record) ? Color.clear : Color.blue.opacity(0.12)
                    )
                    .swipeActions {
                        Button {
                            model.toggleFavorite(record)
                        } label: {
                            Label("Quitar", systemImage: "star.slash")
                        }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        Button {
                            model.toggleFavorite(record)
                        } label: {
                            Label("Quitar de favoritos", systemImage: "star.slash")
                        }
                    }
                }
            }
            .navigationTitle("Favoritos")
            .overlay {
                if model.favoriteHistory.isEmpty {
                    ContentUnavailableView(
                        "Aún no hay favoritos",
                        systemImage: "star",
                        description: Text("Marca un vídeo con la estrella para verlo aquí.")
                    )
                }
            }
            .navigationDestination(for: SummaryRecord.self) { record in
                SummaryDetailView(record: record)
            }
        } detail: {
            ContentUnavailableView(
                "Selecciona un favorito",
                systemImage: "star.square"
            )
        }
    }
}

private struct SummaryRow: View {
    @EnvironmentObject private var model: AppViewModel
    let record: SummaryRecord

    var body: some View {
        HStack(spacing: 10) {
            if !model.isVideoSummaryRead(record) {
                Circle()
                    .fill(.blue)
                    .frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .fontWeight(model.isVideoSummaryRead(record) ? .regular : .semibold)
                    .lineLimit(2)
                HStack {
                    Text(record.createdAt, style: .date)
                    if !model.isVideoSummaryRead(record) {
                        Text("Nuevo")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.isFavorite(record) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorito")
            }
        }
    }
}

private struct SummaryDetailView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let record: SummaryRecord
    @State private var copied = false
    @State private var confirmingDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(record.title).font(.title).bold()
                if let url = record.videoURL {
                    Link(destination: url) {
                        Label("Abrir en YouTube", systemImage: "play.rectangle")
                    }
                }
                Divider()
                Text(record.summary).textSelection(.enabled)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
        }
        .navigationTitle(record.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.toggleFavorite(record)
                } label: {
                    Label(
                        model.isFavorite(record) ? "Quitar de favoritos" : "Añadir a favoritos",
                        systemImage: model.isFavorite(record) ? "star.fill" : "star"
                    )
                }
                Button(action: copySummary) {
                    Label(
                        copied ? "Copiado" : "Copiar",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                Button {
                    confirmingDiscard = true
                } label: {
                    Label("Descartar", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .confirmationDialog(
            "¿Descartar este resumen?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Descartar y volver a resumir", role: .destructive) {
                model.discardSummary(record)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminará el resumen y el vídeo volverá a procesarse la próxima vez que pulses refrescar.")
        }
        .onAppear { model.markVideoSummaryRead(record) }
    }

    private func copySummary() {
        let text = [
            record.title,
            record.videoURL?.absoluteString,
            record.summary
        ].compactMap { $0 }.joined(separator: "\n\n")

        Clipboard.copy(text)

        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
