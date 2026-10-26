import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case youtubeKey
        case channel
        case playlistName
        case playlistID
        case openRouterKey
        case model
        case prompt
    }

    var body: some View {
        Form {
            Section("YouTube") {
                SecureField("API key de YouTube", text: $model.youtubeAPIKey)
                    .focused($focusedField, equals: .youtubeKey)
                TextField("Canal (@handle o ID UC…)", text: $model.settings.channelIdentifier)
                    .focused($focusedField, equals: .channel)
                TextField("Nombre de playlist", text: $model.settings.playlistName)
                    .focused($focusedField, equals: .playlistName)
                TextField("ID de playlist (opcional, recomendado)", text: $model.settings.playlistID)
                    .focused($focusedField, equals: .playlistID)
                Text("El ID de playlist evita tener que buscarla por canal y nombre.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Resumen con OpenRouter") {
                SecureField("API key de OpenRouter", text: $model.openRouterAPIKey)
                    .focused($focusedField, equals: .openRouterKey)
                TextField("Modelo", text: $model.settings.openRouterModel)
                    .focused($focusedField, equals: .model)
                Stepper("Máximo por ejecución: \(model.settings.maximumVideos)", value: $model.settings.maximumVideos, in: 1...20)
                Text("Prompt")
                TextEditor(text: $model.settings.summaryPrompt)
                    .frame(minHeight: 150)
                    .focused($focusedField, equals: .prompt)
            }

            Section {
                Button("Guardar ajustes") { model.saveSettings() }
                    .buttonStyle(.borderedProminent)
            } footer: {
                Text("Las API keys se guardan de forma segura en Keychain.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
        .onTapGesture { focusedField = nil }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focusedField = nil }
            }
        }
        #endif
    }
}
