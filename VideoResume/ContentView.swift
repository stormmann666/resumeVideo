import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            List(model.history) { record in
                NavigationLink(value: record) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).lineLimit(2)
                        Text(record.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("VideoResume")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await model.processNewVideos() }
                    } label: {
                        Label("Buscar vídeos nuevos", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isProcessing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Label("Ajustes", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
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
        } detail: {
            ContentUnavailableView("Selecciona un resumen", systemImage: "doc.text.magnifyingglass")
                .navigationDestination(for: SummaryRecord.self) { record in
                    SummaryDetailView(record: record)
                }
        }
        .toolbar {
            #if os(macOS)
            ToolbarItemGroup {
                Button {
                    Task { await model.processNewVideos() }
                } label: {
                    Label("Buscar vídeos nuevos", systemImage: "arrow.clockwise")
                }
                .disabled(model.isProcessing)
            }
            #endif
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
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") { showingSettings = false }
                        }
                    }
            }
        }
        .emailComposer(draft: $model.emailDraft)
        .alert("VideoResume", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct SummaryDetailView: View {
    @EnvironmentObject private var model: AppViewModel
    let record: SummaryRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(record.title).font(.title).bold()
                if let url = record.videoURL {
                    Link(destination: url) { Label("Abrir en YouTube", systemImage: "play.rectangle") }
                }
                Text(record.summary).textSelection(.enabled)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
        }
        .navigationTitle(record.title)
        .toolbar {
            Button { model.prepareEmail(for: record) } label: {
                Label("Enviar por email", systemImage: "envelope")
            }
        }
    }
}
