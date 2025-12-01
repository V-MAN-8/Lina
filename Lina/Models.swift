import Foundation
struct AIModel: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let url: String
    var isDownloaded: Bool
    var filePath: String
    var size: String
    var downloadProgress: Double
    var downloadedBytes: Int64
    var totalBytes: Int64
    var downloadSpeed: Double
    let createdAt: Date
    var modelfile: Modelfile?
    init(id: UUID = UUID(), name: String, url: String, isDownloaded: Bool = false, filePath: String = "", size: String, downloadProgress: Double = 0.0, downloadedBytes: Int64 = 0, totalBytes: Int64 = 0, downloadSpeed: Double = 0.0, createdAt: Date = Date(), modelfile: Modelfile? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.isDownloaded = isDownloaded
        self.filePath = filePath
        self.size = size
        self.downloadProgress = downloadProgress
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.downloadSpeed = downloadSpeed
        self.createdAt = createdAt
        self.modelfile = modelfile
    }
    var hasModelfile: Bool {
        return modelfile != nil
    }
    enum CodingKeys: String, CodingKey {
        case id, name, url, isDownloaded, filePath, size
        case downloadProgress, downloadedBytes, totalBytes, downloadSpeed, createdAt
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        isDownloaded = try container.decode(Bool.self, forKey: .isDownloaded)
        filePath = try container.decode(String.self, forKey: .filePath)
        size = try container.decode(String.self, forKey: .size)
        downloadProgress = try container.decode(Double.self, forKey: .downloadProgress)
        downloadedBytes = try container.decode(Int64.self, forKey: .downloadedBytes)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        downloadSpeed = try container.decode(Double.self, forKey: .downloadSpeed)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modelfile = nil // Will be extracted from GGUF metadata when needed
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(isDownloaded, forKey: .isDownloaded)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(size, forKey: .size)
        try container.encode(downloadProgress, forKey: .downloadProgress)
        try container.encode(downloadedBytes, forKey: .downloadedBytes)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(downloadSpeed, forKey: .downloadSpeed)
        try container.encode(createdAt, forKey: .createdAt)
    }
    static func == (lhs: AIModel, rhs: AIModel) -> Bool {
        return lhs.id == rhs.id
    }
}
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var content: String
    let isFromUser: Bool
    let timestamp: Date
    var attachedFiles: [AttachedFile]?
    init(id: UUID = UUID(), content: String, isFromUser: Bool, timestamp: Date = Date(), attachedFiles: [AttachedFile]? = nil) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.attachedFiles = attachedFiles
    }
}
struct AttachedFile: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let filePath: String
    let fileType: String
    let fileSize: Int64
    init(id: UUID = UUID(), fileName: String, filePath: String, fileType: String, fileSize: Int64) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.fileType = fileType
        self.fileSize = fileSize
    }
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
enum ModelDownloadStatus {
    case notStarted
    case downloading(progress: Double)
    case completed
    case failed(error: Error)
}
struct HuggingFaceModelInfo: Codable {
    let name: String
    let author: String
    let description: String?
    let downloads: Int
    let likes: Int
    let size: String
    let tags: [String]
    enum CodingKeys: String, CodingKey {
        case name = "modelId"
        case author
        case description
        case downloads
        case likes
        case size
        case tags
    }
}
struct Modelfile: Codable, Equatable {
    var fromPath: String           // FROM: path to .gguf file
    var systemPrompt: String        // SYSTEM: system prompt
    var template: String            // TEMPLATE: chat format template
    var parameters: [String: String] // PARAMETER: key-value pairs
    static let `default` = Modelfile(
        fromPath: "",
        systemPrompt: "You are a helpful AI assistant.",
        template: """
        <|im_start|>system
        {{ .System }}<|im_end|>
        <|im_start|>user
        {{ .Prompt }}<|im_end|>
        <|im_start|>assistant
        """,
        parameters: [
            "num_ctx": "2048",
            "temperature": "0.7",
            "top_p": "0.9",
            "top_k": "40",
            "repeat_penalty": "1.1",
            "num_predict": "256",
            "stop": "<|im_end|>||<|im_start|>"  // Multiple stop sequences separated by ||
        ]
    )
    static func parse(from content: String) -> Modelfile? {
        var fromPath = ""
        var systemPrompt = ""
        var template = ""
        var parameters: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                i += 1
                continue
            }
            if line.hasPrefix("FROM ") {
                fromPath = line.replacingOccurrences(of: "FROM ", with: "").trimmingCharacters(in: .whitespaces)
            }
            else if line.hasPrefix("SYSTEM ") {
                var systemText = line.replacingOccurrences(of: "SYSTEM ", with: "")
                if systemText.hasPrefix("\"\"\"") {
                    systemText = systemText.replacingOccurrences(of: "\"\"\"", with: "")
                    var multiLine = systemText
                    i += 1
                    while i < lines.count && !lines[i].contains("\"\"\"") {
                        multiLine += "\n" + lines[i]
                        i += 1
                    }
                    if i < lines.count {
                        multiLine += "\n" + lines[i].replacingOccurrences(of: "\"\"\"", with: "")
                    }
                    systemPrompt = multiLine.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    systemPrompt = systemText.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            else if line.hasPrefix("TEMPLATE ") {
                var templateText = line.replacingOccurrences(of: "TEMPLATE ", with: "")
                if templateText.hasPrefix("\"\"\"") {
                    templateText = templateText.replacingOccurrences(of: "\"\"\"", with: "")
                    var multiLine = templateText
                    i += 1
                    while i < lines.count && !lines[i].contains("\"\"\"") {
                        multiLine += "\n" + lines[i]
                        i += 1
                    }
                    if i < lines.count {
                        let lastLine = lines[i].replacingOccurrences(of: "\"\"\"", with: "")
                        if !lastLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            multiLine += "\n" + lastLine
                        }
                    }
                    template = multiLine.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    template = templateText.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            else if line.hasPrefix("PARAMETER ") {
                let paramLine = line.replacingOccurrences(of: "PARAMETER ", with: "")
                let components = paramLine.components(separatedBy: " ")
                if components.count >= 2 {
                    let key = components[0]
                    let value = components[1...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if key == "stop" {
                        if let existing = parameters[key] {
                            parameters[key] = existing + "||" + value // Use delimiter for multiple values
                        } else {
                            parameters[key] = value
                        }
                    } else {
                        parameters[key] = value
                    }
                }
            }
            i += 1
        }
        guard !fromPath.isEmpty else { return nil }
        return Modelfile(
            fromPath: fromPath,
            systemPrompt: systemPrompt,
            template: template,
            parameters: parameters
        )
    }
    func toFileContent() -> String {
        var content = "FROM \(fromPath)\n\n"
        if !systemPrompt.isEmpty {
            content += "# System Prompt\n"
            content += "SYSTEM \"\"\"\(systemPrompt)\"\"\"\n\n"
        }
        if !template.isEmpty {
            content += "# Chat Template\n"
            content += "TEMPLATE \"\"\"\n\(template)\n\"\"\"\n\n"
        }
        if !parameters.isEmpty {
            content += "# Parameters\n"
            for (key, value) in parameters.sorted(by: { $0.key < $1.key }) {
                if key == "stop" {
                    let stopValues = value.components(separatedBy: "||")
                    for stopValue in stopValues {
                        content += "PARAMETER stop \"\(stopValue)\"\n"
                    }
                } else {
                    content += "PARAMETER \(key) \(value)\n"
                }
            }
        }
        return content
    }
}
struct ModelConfiguration {
    let contextLength: Int
    let temperature: Float
    let topP: Float
    let topK: Int
    let repeatPenalty: Float
    let maxTokens: Int
    static let `default` = ModelConfiguration(
        contextLength: 2048,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        repeatPenalty: 1.1,
        maxTokens: 256
    )
}
class AppSettings: ObservableObject {
    @Published var selectedModelId: UUID?
    @Published var chatHistory: [ChatMessage] = []
    @Published var modelConfiguration = ModelConfiguration.default
    @Published var autoSaveChatHistory = true
    @Published var enableNotifications = true
    @Published var preferredTheme: AppTheme = .dark
    private let userDefaults = UserDefaults.standard
    init() {
        loadSettings()
    }
    func saveSettings() {
        if let selectedId = selectedModelId {
            userDefaults.set(selectedId.uuidString, forKey: "selectedModelId")
        }
        userDefaults.set(autoSaveChatHistory, forKey: "autoSaveChatHistory")
        userDefaults.set(enableNotifications, forKey: "enableNotifications")
        userDefaults.set(preferredTheme.rawValue, forKey: "preferredTheme")
    }
    private func loadSettings() {
        if let savedModelId = userDefaults.string(forKey: "selectedModelId"),
           let uuid = UUID(uuidString: savedModelId) {
            selectedModelId = uuid
        }
        autoSaveChatHistory = userDefaults.bool(forKey: "autoSaveChatHistory")
        enableNotifications = userDefaults.bool(forKey: "enableNotifications")
        if let themeRawValue = userDefaults.object(forKey: "preferredTheme") as? String,
           let theme = AppTheme(rawValue: themeRawValue) {
            preferredTheme = theme
        }
    }
}
enum AppTheme: String, CaseIterable {
    case dark = "dark"
    case system = "system"
    var displayName: String {
        switch self {
        case .dark:
            return "Dark"
        case .system:
            return "System"
        }
    }
}
enum LinaError: LocalizedError {
    case modelNotFound
    case downloadFailed(String)
    case invalidModelFormat
    case llamaCppError(String)
    case networkError
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model not found"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .invalidModelFormat:
            return "Invalid model format"
        case .llamaCppError(let message):
            return "Llama.cpp error: \(message)"
        case .networkError:
            return "Network connection error"
        }
    }
}
