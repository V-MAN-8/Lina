import Foundation
import Network
class FileManagerUtility {
    static let shared = FileManagerUtility()
    private let fileManager = FileManager.default
    private init() {}
    var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    var modelsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Models")
        createDirectoryIfNeeded(at: url)
        return url
    }
    var chatHistoryDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("ChatHistory")
        createDirectoryIfNeeded(at: url)
        return url
    }
    func createDirectoryIfNeeded(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
    func saveModel(_ model: AIModel, data: Data) throws -> String {
        let fileName = "\(model.id.uuidString).gguf"
        let fileURL = modelsDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        return fileURL.path
    }
    func deleteModel(_ model: AIModel) throws {
        guard !model.filePath.isEmpty else { return }
        let fileURL = URL(fileURLWithPath: model.filePath)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    func getModelFileSize(_ model: AIModel) -> Int64 {
        guard !model.filePath.isEmpty else { return 0 }
        let fileURL = URL(fileURLWithPath: model.filePath)
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    func saveChatHistory(_ messages: [ChatMessage]) throws {
        let fileName = "chat_history_\(Date().timeIntervalSince1970).json"
        let fileURL = chatHistoryDirectory.appendingPathComponent(fileName)
        let data = try JSONEncoder().encode(messages)
        try data.write(to: fileURL)
    }
    func loadChatHistory() -> [ChatMessage] {
        do {
            let files = try fileManager.contentsOfDirectory(at: chatHistoryDirectory, includingPropertiesForKeys: nil)
            let chatFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("chat_history_") }
            guard let latestFile = chatFiles.max(by: { $0.lastPathComponent < $1.lastPathComponent }) else {
                return []
            }
            let data = try Data(contentsOf: latestFile)
            return try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch {
            print("Failed to load chat history: \(error)")
            return []
        }
    }
}
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private init() {
        startMonitoring()
    }
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }
    func stopMonitoring() {
        monitor.cancel()
    }
}
class ModelDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloadManager()
    private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]
    private var progressHandlers: [UUID: (Double, Int64, Int64, Double) -> Void] = [:]
    private var completionHandlers: [UUID: (Result<String, Error>) -> Void] = [:]
    private var lastUpdateTimes: [UUID: Date] = [:]
    private var lastDownloadedBytes: [UUID: Int64] = [:]
    private var downloadSpeeds: [UUID: Double] = [:]
    private var resumeData: [UUID: Data] = [:] // Store resume data for interrupted downloads
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.lina.modeldownload")
        config.isDiscretionary = false // Download immediately
        config.sessionSendsLaunchEvents = true // Wake app when download completes
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private let resumeDataDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let resumeDir = appSupport.appendingPathComponent("Lina/ResumeData")
        try? FileManager.default.createDirectory(at: resumeDir, withIntermediateDirectories: true)
        return resumeDir
    }()
    private override init() {
        super.init()
        loadResumeData()
    }
    private func saveResumeDataToDisk(_ data: Data, for modelId: UUID) {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(modelId.uuidString).resume")
        try? data.write(to: fileURL)
        print("[Download] Saved resume data for model \(modelId)")
    }
    private func loadResumeData() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: resumeDataDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "resume" {
            if let data = try? Data(contentsOf: file) {
                let modelIdString = file.deletingPathExtension().lastPathComponent
                if let modelId = UUID(uuidString: modelIdString) {
                    resumeData[modelId] = data
                    print("[Download] Loaded resume data for model \(modelId)")
                }
            }
        }
    }
    private func deleteResumeData(for modelId: UUID) {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(modelId.uuidString).resume")
        try? FileManager.default.removeItem(at: fileURL)
        resumeData.removeValue(forKey: modelId)
    }
    func resumeIncompleteDownloads(models: [AIModel]) {
        print("[Download] Checking for incomplete downloads to resume...")
        for model in models where !model.isDownloaded && model.downloadProgress > 0 {
            if let data = resumeData[model.id] {
                print("[Download] Resuming download for: \(model.name)")
                let task = session.downloadTask(withResumeData: data)
                downloadTasks[model.id] = task
                task.resume()
            }
        }
    }
    func downloadModel(_ model: AIModel, progressHandler: @escaping (Double, Int64, Int64, Double) -> Void, completionHandler: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: model.url) else {
            completionHandler(.failure(LinaError.networkError))
            return
        }
        let task = session.downloadTask(with: url)
        downloadTasks[model.id] = task
        progressHandlers[model.id] = progressHandler
        completionHandlers[model.id] = completionHandler
        lastUpdateTimes[model.id] = Date()
        lastDownloadedBytes[model.id] = 0
        downloadSpeeds[model.id] = 0.0
        task.resume()
    }
    func cancelDownload(for modelId: UUID) {
        if let task = downloadTasks[modelId] {
            task.cancel { [weak self] resumeDataOrNil in
                if let data = resumeDataOrNil {
                    self?.resumeData[modelId] = data
                    self?.saveResumeDataToDisk(data, for: modelId)
                    print("[Download] Saved resume data for canceled download: \(modelId)")
                }
            }
            downloadTasks.removeValue(forKey: modelId)
            progressHandlers.removeValue(forKey: modelId)
            completionHandlers.removeValue(forKey: modelId)
            lastUpdateTimes.removeValue(forKey: modelId)
            lastDownloadedBytes.removeValue(forKey: modelId)
            downloadSpeeds.removeValue(forKey: modelId)
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let modelId = downloadTasks.first(where: { $0.value == downloadTask })?.key,
              let progressHandler = progressHandlers[modelId] else {
            return
        }
        let currentTime = Date()
        let lastTime = lastUpdateTimes[modelId] ?? currentTime
        let timeInterval = currentTime.timeIntervalSince(lastTime)
        let isFirstUpdate = lastUpdateTimes[modelId] == nil || lastDownloadedBytes[modelId] == nil
        if isFirstUpdate || timeInterval >= 0.2 {
            let bytesDownloadedSinceLastUpdate = totalBytesWritten - (lastDownloadedBytes[modelId] ?? 0)
            let speedMBps = timeInterval > 0 ? Double(bytesDownloadedSinceLastUpdate) / (1024 * 1024) / timeInterval : 0.0
            let previousSpeed = downloadSpeeds[modelId] ?? 0.0
            let smoothedSpeed = isFirstUpdate ? speedMBps : (previousSpeed * 0.7 + speedMBps * 0.3)
            lastUpdateTimes[modelId] = currentTime
            lastDownloadedBytes[modelId] = totalBytesWritten
            downloadSpeeds[modelId] = smoothedSpeed
            let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
            progressHandler(progress, totalBytesWritten, totalBytesExpectedToWrite, smoothedSpeed)
            if isFirstUpdate || Int(totalBytesWritten / (10 * 1024 * 1024)) > Int((lastDownloadedBytes[modelId] ?? 0) / (10 * 1024 * 1024)) {
                print("[Download] Progress: \(String(format: "%.1f", progress * 100))% - Downloaded: \(totalBytesWritten / (1024 * 1024)) MB / \(totalBytesExpectedToWrite / (1024 * 1024)) MB - Speed: \(String(format: "%.2f", smoothedSpeed)) MB/s")
            }
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let modelId = downloadTasks.first(where: { $0.value == downloadTask })?.key,
              let completionHandler = completionHandlers[modelId] else {
            return
        }
        do {
            let fileName = "\(modelId.uuidString).gguf"
            let destinationURL = FileManagerUtility.shared.modelsDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            downloadTasks.removeValue(forKey: modelId)
            progressHandlers.removeValue(forKey: modelId)
            completionHandlers.removeValue(forKey: modelId)
            deleteResumeData(for: modelId)
            completionHandler(.success(destinationURL.path))
        } catch {
            completionHandler(.failure(error))
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let modelId = downloadTasks.first(where: { $0.value == downloadTask })?.key else {
            return
        }
        if let error = error {
            let nsError = error as NSError
            if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                self.resumeData[modelId] = resumeData
                saveResumeDataToDisk(resumeData, for: modelId)
                print("[Download] Saved resume data due to error: \(error.localizedDescription)")
            }
            if let completionHandler = completionHandlers[modelId] {
                completionHandler(.failure(error))
            }
        }
        downloadTasks.removeValue(forKey: modelId)
        progressHandlers.removeValue(forKey: modelId)
        completionHandlers.removeValue(forKey: modelId)
        lastUpdateTimes.removeValue(forKey: modelId)
        lastDownloadedBytes.removeValue(forKey: modelId)
        downloadSpeeds.removeValue(forKey: modelId)
    }
}
class HuggingFaceAPIClient {
    static let shared = HuggingFaceAPIClient()
    private let baseURL = "https://huggingface.co/api"
    private let session = URLSession.shared
    private init() {}
    func fetchModelInfo(from modelURL: String) async throws -> HuggingFaceModelInfo {
        guard let modelPath = extractModelPath(from: modelURL) else {
            throw LinaError.invalidModelFormat
        }
        let apiURL = URL(string: "\(baseURL)/models/\(modelPath)")!
        let (data, response) = try await session.data(from: apiURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LinaError.networkError
        }
        let modelInfo = try JSONDecoder().decode(HuggingFaceModelInfo.self, from: data)
        return modelInfo
    }
    func downloadModel(from url: String, progressHandler: @escaping (Double) -> Void) async throws -> Data {
        guard let downloadURL = URL(string: url) else {
            throw LinaError.networkError
        }
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: downloadURL) { localURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let localURL = localURL else {
                    continuation.resume(throwing: LinaError.downloadFailed("No local URL"))
                    return
                }
                do {
                    let data = try Data(contentsOf: localURL)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            _ = task.progress.observe(\.fractionCompleted) { progress, _ in
                DispatchQueue.main.async {
                    progressHandler(progress.fractionCompleted)
                }
            }
            task.resume()
        }
    }
    private func extractModelPath(from url: String) -> String? {
        let components = url.components(separatedBy: "/")
        guard components.count >= 5,
              components[2] == "huggingface.co" else {
            return nil
        }
        return "\(components[3])/\(components[4])"
    }
}
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published var currentTheme: AppTheme = .dark
    private init() {
        loadTheme()
    }
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "selectedTheme")
    }
    private func loadTheme() {
        if let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            currentTheme = theme
        }
    }
}
class AnalyticsManager {
    static let shared = AnalyticsManager()
    private init() {}
    func trackEvent(_ event: AnalyticsEvent) {
        print("Analytics Event: \(event.name) - \(event.parameters)")
    }
}
struct AnalyticsEvent {
    let name: String
    let parameters: [String: Any]
    static func modelDownloadStarted(modelName: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "model_download_started", parameters: ["model_type": "unknown"])
    }
    static func modelDownloadCompleted(success: Bool) -> AnalyticsEvent {
        AnalyticsEvent(name: "model_download_completed", parameters: ["success": success])
    }
    static func chatMessageSent() -> AnalyticsEvent {
        AnalyticsEvent(name: "chat_message_sent", parameters: [:])
    }
    static func modelLoaded(modelName: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "model_loaded", parameters: ["model_type": "unknown"])
    }
}
extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
extension String {
    var isValidURL: Bool {
        URL(string: self) != nil
    }
}
