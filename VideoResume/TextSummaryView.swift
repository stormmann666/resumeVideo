import SwiftUI
import PhotosUI

struct TextSummaryLibraryView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showingNewSummary = false

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(model.textHistory) { record in
                    NavigationLink(value: record) {
                        HStack(spacing: 12) {
                            Image(systemName: record.source.systemImage)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title).lineLimit(2)
                                HStack {
                                    Text(record.source.title)
                                    Text("·")
                                    Text(record.createdAt, style: .date)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.deleteTextSummary(record)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            model.deleteTextSummary(record)
                        } label: {
                            Label("Borrar resumen", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: model.deleteTextSummaries)
            }
            .navigationTitle("Texto y OCR")
            .toolbar {
                ToolbarItem(placement: addPlacement) {
                    Button { showingNewSummary = true } label: {
                        Label("Nuevo resumen", systemImage: "plus")
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                #endif
            }
            .overlay {
                if model.textHistory.isEmpty {
                    ContentUnavailableView(
                        "Aún no hay resúmenes de texto",
                        systemImage: "text.viewfinder",
                        description: Text("Añade fotos o pega texto desde el portapapeles.")
                    )
                }
            }
            .navigationDestination(for: TextSummaryRecord.self) { record in
                TextSummaryDetailView(record: record)
            }
        } detail: {
            ContentUnavailableView(
                "Selecciona un resumen",
                systemImage: "doc.text.magnifyingglass"
            )
        }
        .sheet(isPresented: $showingNewSummary) {
            NavigationStack {
                NewTextSummaryView()
            }
            #if os(macOS)
            .frame(minWidth: 580, minHeight: 650)
            #endif
        }
        .alert("VideoResume", isPresented: Binding(
            get: { model.errorMessage != nil && !showingNewSummary },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var addPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }
}

private struct NewTextSummaryView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var source: TextSummarySource = .photoOCR
    @State private var title = ""
    @State private var inputText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isRecognizing = false
    @State private var recognitionError: String?
    @FocusState private var focusedField: Field?

    private let ocr = OCRService()

    private enum Field: Hashable { case title, content }

    var body: some View {
        Form {
            Section {
                Picker("Origen", selection: $source) {
                    Label("Foto OCR", systemImage: "text.viewfinder")
                        .tag(TextSummarySource.photoOCR)
                    Label("Portapapeles", systemImage: "doc.on.clipboard")
                        .tag(TextSummarySource.clipboard)
                }
                .pickerStyle(.segmented)
            }

            Section("Contenido") {
                if source == .photoOCR {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label(
                            selectedPhotos.isEmpty ? "Seleccionar fotos" : "\(selectedPhotos.count) foto(s) seleccionada(s)",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    if isRecognizing {
                        HStack {
                            ProgressView()
                            Text("Reconociendo texto…")
                        }
                    }
                } else {
                    Button(action: pasteFromClipboard) {
                        Label("Pegar desde el portapapeles", systemImage: "doc.on.clipboard")
                    }
                }

                TextEditor(text: $inputText)
                    .focused($focusedField, equals: .content)
                    .frame(minHeight: 220)
                    .overlay(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text(source == .photoOCR ? "Aquí aparecerá el texto reconocido…" : "Pega o escribe aquí el texto…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Section("Nombre") {
                TextField("Título opcional", text: $title)
                    .focused($focusedField, equals: .title)
            }

            Section {
                Button {
                    Task {
                        if await model.createTextSummary(title: title, text: inputText, source: source) {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if model.isTextProcessing { ProgressView().controlSize(.small) }
                        Label("Resumir y guardar", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRecognizing || model.isTextProcessing)
            } footer: {
                Text("El resultado se guardará en la biblioteca Texto/OCR, separada de YouTube.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nuevo resumen")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focusedField = nil }
            }
            #endif
        }
        .onChange(of: selectedPhotos) { _, _ in
            Task { await recognizeSelectedPhotos() }
        }
        .onTapGesture { focusedField = nil }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .alert("No se pudo leer el contenido", isPresented: Binding(
            get: { recognitionError != nil },
            set: { if !$0 { recognitionError = nil } }
        )) {
            Button("OK", role: .cancel) { recognitionError = nil }
        } message: {
            Text(recognitionError ?? "")
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

    private func pasteFromClipboard() {
        guard let text = Clipboard.text, !text.isEmpty else {
            recognitionError = "El portapapeles no contiene texto."
            return
        }
        inputText = text
        focusedField = .content
    }

    @MainActor
    private func recognizeSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            var pages: [String] = []
            for item in selectedPhotos {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                pages.append(try await ocr.recognizeText(in: data))
            }
            guard !pages.isEmpty else { throw VideoResumeError.noContent("las imágenes") }
            inputText = pages.joined(separator: "\n\n———\n\n")
        } catch {
            recognitionError = error.localizedDescription
        }
    }
}

private struct TextSummaryDetailView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let record: TextSummaryRecord
    @State private var copied = false
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(record.title).font(.title).bold()
                Label(record.source.title, systemImage: record.source.systemImage)
                    .foregroundStyle(.secondary)
                Divider()
                Text(record.summary).textSelection(.enabled)
                DisclosureGroup("Texto original") {
                    Text(record.originalText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
        }
        .navigationTitle(record.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Clipboard.copy(record.summary)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copiado" : "Copiar resumen", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Menu {
                    Button {
                        Clipboard.copy(record.originalText)
                    } label: {
                        Label("Copiar texto original", systemImage: "doc.on.clipboard")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Borrar resumen", systemImage: "trash")
                    }
                } label: {
                    Label("Más", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("¿Borrar este resumen?", isPresented: $confirmingDelete) {
            Button("Borrar", role: .destructive) {
                model.deleteTextSummary(record)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}
