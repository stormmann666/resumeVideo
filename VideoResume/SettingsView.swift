import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Form {
            Section("YouTube") {
                SecureField("API key de YouTube", text: $model.youtubeAPIKey)
                TextField("Canal (@handle o ID UC…)", text: $model.settings.channelIdentifier)
                TextField("Nombre de playlist", text: $model.settings.playlistName)
                TextField("ID de playlist (opcional, recomendado)", text: $model.settings.playlistID)
                Text("El ID de playlist evita tener que buscarla por canal y nombre.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Resumen con OpenRouter") {
                SecureField("API key de OpenRouter", text: $model.openRouterAPIKey)
                TextField("Modelo", text: $model.settings.openRouterModel)
                Stepper("Máximo por ejecución: \(model.settings.maximumVideos)", value: $model.settings.maximumVideos, in: 1...20)
                Text("Prompt")
                TextEditor(text: $model.settings.summaryPrompt)
                    .frame(minHeight: 150)
            }

            Section("Entrega") {
                TextField("Email destinatario", text: $model.settings.recipientEmail)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
            }

            Section {
                Button("Guardar ajustes") { model.saveSettings() }
                    .buttonStyle(.borderedProminent)
            } footer: {
                Text("Las API keys se guardan en Keychain. El envío se confirma en la app Mail del dispositivo.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
    }
}
