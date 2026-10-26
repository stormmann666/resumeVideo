import Foundation

struct SettingsStore {
    private let settingsKey = "videoResume.settings.v1"
    private let historyKey = "videoResume.history.v1"
    private let defaults = UserDefaults.standard

    func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return value
    }

    func saveSettings(_ settings: AppSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: settingsKey)
    }

    func loadHistory() -> [SummaryRecord] {
        guard let data = defaults.data(forKey: historyKey),
              let value = try? JSONDecoder().decode([SummaryRecord].self, from: data) else {
            return []
        }
        return value.sorted { $0.createdAt > $1.createdAt }
    }

    func saveHistory(_ records: [SummaryRecord]) throws {
        defaults.set(try JSONEncoder().encode(records), forKey: historyKey)
    }
}
