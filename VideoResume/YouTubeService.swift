import Foundation

struct YouTubeService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestVideos(settings: AppSettings, apiKey: String) async throws -> [VideoItem] {
        let playlistID: String
        if !settings.playlistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            playlistID = settings.playlistID.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let channelID = try await resolveChannelID(settings.channelIdentifier, apiKey: apiKey)
            playlistID = try await resolvePlaylistID(
                named: settings.playlistName,
                channelID: channelID,
                apiKey: apiKey
            )
        }
        return try await playlistItems(playlistID: playlistID, apiKey: apiKey)
    }

    func transcript(for video: VideoItem) async -> String? {
        guard let listURL = URL(string: "https://www.youtube.com/api/timedtext?type=list&v=\(video.id)"),
              let (trackData, _) = try? await session.data(from: listURL) else { return nil }
        let tracks = CaptionTrackParser.parse(trackData)
        guard let track = tracks.first(where: { $0.language.hasPrefix("es") }) ?? tracks.first(where: { $0.language.hasPrefix("en") }) ?? tracks.first else {
            return nil
        }
        var components = URLComponents(string: "https://www.youtube.com/api/timedtext")
        components?.queryItems = [
            URLQueryItem(name: "v", value: video.id),
            URLQueryItem(name: "lang", value: track.language),
            URLQueryItem(name: "name", value: track.name)
        ]
        guard let url = components?.url,
              let (data, _) = try? await session.data(from: url) else { return nil }
        let lines = CaptionTextParser.parse(data)
        let text = lines.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func resolveChannelID(_ identifier: String, apiKey: String) async throws -> String {
        let clean = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw VideoResumeError.missingSettings("canal de YouTube") }
        if clean.hasPrefix("UC") { return clean }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "id"),
            URLQueryItem(name: "forHandle", value: clean.replacingOccurrences(of: "@", with: "")),
            URLQueryItem(name: "key", value: apiKey)
        ]
        let response: ChannelResponse = try await request(components.url!)
        guard let id = response.items.first?.id else {
            throw VideoResumeError.api("No se encontró el canal \(identifier).")
        }
        return id
    }

    private func resolvePlaylistID(named name: String, channelID: String, apiKey: String) async throws -> String {
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlists")!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "channelId", value: channelID),
                URLQueryItem(name: "maxResults", value: "50"),
                URLQueryItem(name: "pageToken", value: pageToken),
                URLQueryItem(name: "key", value: apiKey)
            ].filter { $0.value != nil }
            let response: PlaylistResponse = try await request(components.url!)
            if let match = response.items.first(where: {
                $0.snippet.title.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) { return match.id }
            pageToken = response.nextPageToken
        } while pageToken != nil
        throw VideoResumeError.playlistNotFound(name)
    }

    private func playlistItems(playlistID: String, apiKey: String) async throws -> [VideoItem] {
        var output: [VideoItem] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "playlistId", value: playlistID),
                URLQueryItem(name: "maxResults", value: "50"),
                URLQueryItem(name: "pageToken", value: pageToken),
                URLQueryItem(name: "key", value: apiKey)
            ].filter { $0.value != nil }
            let response: PlaylistItemsResponse = try await request(components.url!)
            output.append(contentsOf: response.items.compactMap { item in
                guard let id = item.snippet.resourceId.videoId,
                      item.snippet.title != "Deleted video",
                      item.snippet.title != "Private video" else { return nil }
                return VideoItem(
                    id: id,
                    title: item.snippet.title,
                    description: item.snippet.description,
                    addedAt: item.snippet.publishedAt
                )
            })
            pageToken = response.nextPageToken
        } while pageToken != nil && output.count < 200
        return output.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw VideoResumeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data)
            throw VideoResumeError.api(apiError?.error.message ?? "YouTube devolvió el error HTTP \(http.statusCode).")
        }
        return try JSONDecoder.youtube.decode(T.self, from: data)
    }
}

private struct ChannelResponse: Decodable { let items: [ChannelItem] }
private struct ChannelItem: Decodable { let id: String }
private struct PlaylistResponse: Decodable { let items: [Playlist]; let nextPageToken: String? }
private struct Playlist: Decodable { let id: String; let snippet: PlaylistSnippet }
private struct PlaylistSnippet: Decodable { let title: String }
private struct PlaylistItemsResponse: Decodable { let items: [PlaylistEntry]; let nextPageToken: String? }
private struct PlaylistEntry: Decodable { let snippet: PlaylistItemSnippet }
private struct PlaylistItemSnippet: Decodable {
    let publishedAt: Date?
    let title: String
    let description: String
    let resourceId: ResourceID
}
private struct ResourceID: Decodable { let videoId: String? }
private struct GoogleErrorEnvelope: Decodable { let error: GoogleAPIError }
private struct GoogleAPIError: Decodable { let message: String }

private extension JSONDecoder {
    static var youtube: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct CaptionTrack { let language: String; let name: String }

private final class CaptionTrackParser: NSObject, XMLParserDelegate {
    private var tracks: [CaptionTrack] = []

    static func parse(_ data: Data) -> [CaptionTrack] {
        let delegate = CaptionTrackParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.tracks
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "track", let language = attributeDict["lang_code"] else { return }
        tracks.append(CaptionTrack(language: language, name: attributeDict["name"] ?? ""))
    }
}

private final class CaptionTextParser: NSObject, XMLParserDelegate {
    private var lines: [String] = []
    private var current = ""

    static func parse(_ data: Data) -> [String] {
        let delegate = CaptionTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.lines
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { current += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "text" else { return }
        lines.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        current = ""
    }
}
