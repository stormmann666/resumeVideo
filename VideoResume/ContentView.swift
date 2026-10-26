import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    var body: some View {
        TabView {
            SummaryLibraryView()
                .tabItem { Label("Resúmenes", systemImage: "doc.text") }

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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title).lineLimit(2)
                            Text(record.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.deleteSummary(record)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                    .contextMenu {
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
    }

    private func copySummary() {
        let text = [
            record.title,
            record.videoURL?.absoluteString,
            record.summary
        ].compactMap { $0 }.joined(separator: "\n\n")

        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
