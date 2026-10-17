import Foundation

struct HuggingFaceUser: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let fullname: String?
    let isPro: Bool
    let avatarUrl: String?
}

struct HuggingFaceModel: Codable, Sendable, Identifiable {
    let id: String
    let likes: Int
    let downloads: Int
    let isPrivate: Bool
    let pipelineTag: String?
    let createdAt: Date?

    var repoName: String {
        id.components(separatedBy: "/").last ?? id
    }

    var url: String {
        "https://huggingface.co/\(id)"
    }
}

struct HuggingFaceDataset: Codable, Sendable, Identifiable {
    let id: String
    let likes: Int
    let downloads: Int
    let isPrivate: Bool
    let createdAt: Date?

    var repoName: String {
        id.components(separatedBy: "/").last ?? id
    }

    var url: String {
        "https://huggingface.co/datasets/\(id)"
    }
}

struct HuggingFaceSpace: Codable, Sendable, Identifiable {
    let id: String
    let likes: Int
    let isPrivate: Bool
    let stage: String?

    var repoName: String {
        id.components(separatedBy: "/").last ?? id
    }

    var url: String {
        "https://huggingface.co/spaces/\(id)"
    }
}

final class HuggingFacePoller: @unchecked Sendable {
    static let shared = HuggingFacePoller()
    private var timer: DispatchSourceTimer?
    private var lastPoll: Date?
    private init() {}

    static var isUsingLocalToken: Bool {
        if let key = KeychainStore.shared.get("huggingface-api-key"), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return readLocalToken() != nil
    }

    static func readLocalToken() -> String? {
        let cachePath = NSString(string: "~/.cache/huggingface/token").expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
           let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        let legacyPath = NSString(string: "~/.huggingface/token").expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: legacyPath)),
           let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        if let env = ProcessInfo.processInfo.environment["HF_TOKEN"], !env.isEmpty {
            return env
        }
        return nil
    }

    var token: String? {
        if let key = KeychainStore.shared.get("huggingface-api-key"), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Self.readLocalToken()
    }

    var hasToken: Bool {
        token != nil
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 8, repeating: 300, leeway: .seconds(30))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func pollNow() {
        poll()
    }

    func refreshIfStale() {
        if let last = lastPoll, Date().timeIntervalSince(last) < 60 { return }
        poll()
    }

    private func poll() {
        guard !DemoEngine.isPollerPaused else { return }
        guard let token = self.token else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AppState.shared.huggingFaceLoaded = false
                }
            }
            return
        }

        lastPoll = Date()

        guard let whoamiURL = URL(string: "https://huggingface.co/api/whoami-v2") else { return }
        var req = URLRequest(url: whoamiURL, timeoutInterval: 12)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                let msg: String
                if code == 401 { msg = "Invalid Hugging Face token (401)" }
                else if code == 0 { msg = error?.localizedDescription ?? "No connection" }
                else { msg = "API error \(code)" }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        AppState.shared.huggingFaceError = msg
                    }
                }
                return
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            guard let name = json["name"] as? String else { return }
            let id = (json["id"] as? String) ?? name
            let fullname = json["fullname"] as? String
            let isPro = (json["isPro"] as? Bool) ?? false
            let avatarUrl = json["avatarUrl"] as? String

            let user = HuggingFaceUser(id: id, name: name, fullname: fullname, isPro: isPro, avatarUrl: avatarUrl)

            self.fetchResources(username: name, token: token, user: user)
        }.resume()
    }

    private func fetchResources(username: String, token: String, user: HuggingFaceUser) {
        let group = DispatchGroup()

        var models: [HuggingFaceModel] = []
        var datasets: [HuggingFaceDataset] = []
        var spaces: [HuggingFaceSpace] = []

        // Models
        group.enter()
        if let modelsURL = URL(string: "https://huggingface.co/api/models?author=\(username)&limit=50&full=true") {
            var req = URLRequest(url: modelsURL, timeoutInterval: 12)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                if let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    models = list.compactMap { self.parseModel($0) }
                }
            }.resume()
        } else {
            group.leave()
        }

        // Datasets
        group.enter()
        if let datasetsURL = URL(string: "https://huggingface.co/api/datasets?author=\(username)&limit=50&full=true") {
            var req = URLRequest(url: datasetsURL, timeoutInterval: 12)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                if let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    datasets = list.compactMap { self.parseDataset($0) }
                }
            }.resume()
        } else {
            group.leave()
        }

        // Spaces
        group.enter()
        if let spacesURL = URL(string: "https://huggingface.co/api/spaces?author=\(username)&limit=50&full=true") {
            var req = URLRequest(url: spacesURL, timeoutInterval: 12)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                if let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    spaces = list.compactMap { self.parseSpace($0) }
                }
            }.resume()
        } else {
            group.leave()
        }

        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                AppState.shared.huggingFaceUser = user
                AppState.shared.huggingFaceModels = models
                AppState.shared.huggingFaceDatasets = datasets
                AppState.shared.huggingFaceSpaces = spaces
                AppState.shared.huggingFaceLoaded = true
                AppState.shared.huggingFaceError = nil
            }
        }
    }

    private func parseDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }

    private func parseModel(_ dict: [String: Any]) -> HuggingFaceModel? {
        guard let id = (dict["id"] as? String) ?? (dict["modelId"] as? String) else { return nil }
        let likes = (dict["likes"] as? Int) ?? 0
        let downloads = (dict["downloads"] as? Int) ?? 0
        let isPrivate = (dict["private"] as? Bool) ?? false
        let pipelineTag = dict["pipeline_tag"] as? String
        let createdAt = parseDate(dict["createdAt"] as? String)
        return HuggingFaceModel(id: id, likes: likes, downloads: downloads, isPrivate: isPrivate, pipelineTag: pipelineTag, createdAt: createdAt)
    }

    private func parseDataset(_ dict: [String: Any]) -> HuggingFaceDataset? {
        guard let id = dict["id"] as? String else { return nil }
        let likes = (dict["likes"] as? Int) ?? 0
        let downloads = (dict["downloads"] as? Int) ?? 0
        let isPrivate = (dict["private"] as? Bool) ?? false
        let createdAt = parseDate(dict["createdAt"] as? String)
        return HuggingFaceDataset(id: id, likes: likes, downloads: downloads, isPrivate: isPrivate, createdAt: createdAt)
    }

    private func parseSpace(_ dict: [String: Any]) -> HuggingFaceSpace? {
        guard let id = dict["id"] as? String else { return nil }
        let likes = (dict["likes"] as? Int) ?? 0
        let isPrivate = (dict["private"] as? Bool) ?? false
        var stage: String? = nil
        if let runtime = dict["runtime"] as? [String: Any] {
            stage = runtime["stage"] as? String
        }
        return HuggingFaceSpace(id: id, likes: likes, isPrivate: isPrivate, stage: stage)
    }
}
