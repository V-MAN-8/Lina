import Foundation
import Combine
class LlamaCPPManager: ObservableObject {
    static let shared = LlamaCPPManager()
    @Published var isModelLoaded = false
    @Published var currentModel: AIModel?
    @Published var loadingProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var isGenerating = false
    @Published var isInstallingLlamaCPP = false
    @Published var llamaCPPInstallProgress: Double = 0.0
    @Published var llamaCPPInstallStatus: String = ""
    private let defaultContextLength = 4096      // Official default: 4096
    private let defaultMaxTokens = 2048           // Reasonable generation limit
    private let defaultTemperature: Float = 0.8  // Official default: 0.8
    private let defaultTopP: Float = 0.9         // Official default: 0.9
    private let defaultTopK = 40                 // Official default: 40
    private let defaultRepeatPenalty: Float = 1.0 // Official default: 1.0 (disabled)
    private let defaultRepeatLastN = 64          // Standard context window for penalties
    private var templateCache: [String: String?] = [:]
    private let templateCacheLock = NSLock()
    private var cachedLlamaCLIPath: String? = nil
    private var hasDetectedLlamaCLI: Bool = false
    private let llamaCLIDetectionLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    private var processQueue = DispatchQueue(label: "com.lina.llamaProcess", qos: .userInitiated)
    private var streamingBuffer = ""
    private var lastTokenTime: Date = Date()
    private var tokenCount = 0
    private var sessionProcesses: [UUID: Process] = [:] // Each session has its own llama.cpp process
    private var sessionLock = NSLock()
    private var currentProcess: Process?
    private var processLock = NSLock()
    private init() {
        print("[LlamaCPP] Manager initialized")
    }
    deinit {
        unloadModel()
    }
    func extractChatTemplateForModel(modelPath: String) -> String? {
        return extractChatTemplateFromGGUF(modelPath: modelPath)
    }
    private func extractChatTemplateFromGGUF(modelPath: String) -> String? {
        templateCacheLock.lock()
        if let cached = templateCache[modelPath] {
            templateCacheLock.unlock()
            return cached
        }
        templateCacheLock.unlock()
        guard let llamaCLIPath = detectLlamaCLI() else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: llamaCLIPath)
        task.arguments = ["-m", modelPath, "--verbose", "-n", "0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        var extractedTemplate: String? = nil
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("tokenizer.chat_template") || trimmed.contains("chat_template") {
                        if let equalIndex = trimmed.firstIndex(of: "=") {
                            let afterEqual = trimmed[trimmed.index(after: equalIndex)...]
                            let templateValue = afterEqual.trimmingCharacters(in: .whitespaces)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                            if !templateValue.isEmpty && templateValue.count > 10 {
                                extractedTemplate = templateValue
                                break
                            }
                        }
                    }
                }
            }
        } catch {}
        templateCacheLock.lock()
        templateCache[modelPath] = extractedTemplate
        templateCacheLock.unlock()
        return extractedTemplate
    }
    func loadModel(_ model: AIModel) {
        guard model.isDownloaded, !model.filePath.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "Model is not downloaded"
            }
            return
        }
        guard FileManager.default.fileExists(atPath: model.filePath) else {
            DispatchQueue.main.async {
                self.errorMessage = "Model file not found"
            }
            return
        }
        unloadModel()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.loadingProgress = 0.5
            }
            Thread.sleep(forTimeInterval: 0.5)
            DispatchQueue.main.async {
                self.loadingProgress = 1.0
                self.isModelLoaded = true
                self.currentModel = model
                self.errorMessage = nil
                print("[LlamaCPP] Model ready: \(model.name)")
            }
        }
    }
    func unloadModel() {
        isModelLoaded = false
        currentModel = nil
        loadingProgress = 0.0
        isGenerating = false
        errorMessage = nil
        streamingBuffer = ""
        tokenCount = 0
        print("[LlamaCPP] Model unloaded")
    }
    func stopGeneration(for sessionId: UUID? = nil) {
        print("[LlamaCPP] Stopping generation process")
        sessionLock.lock()
        if let sessionId = sessionId {
            if let process = sessionProcesses[sessionId], process.isRunning {
                process.terminate()
                sessionProcesses.removeValue(forKey: sessionId)
                print("[LlamaCPP] Terminated process for session: \(sessionId.uuidString.prefix(8))")
            }
        } else {
            if let process = currentProcess, process.isRunning {
                process.terminate()
                print("[LlamaCPP] Process terminated successfully")
            }
        }
        currentProcess = nil
        sessionLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.isGenerating = false
        }
    }
    func stopAllSessions() {
        print("[LlamaCPP] Stopping all session processes")
        sessionLock.lock()
        for (sessionId, process) in sessionProcesses {
            if process.isRunning {
                process.terminate()
                print("[LlamaCPP] Terminated process for session: \(sessionId.uuidString.prefix(8))")
            }
        }
        sessionProcesses.removeAll()
        currentProcess = nil
        sessionLock.unlock()
        print("[LlamaCPP] All session processes stopped")
    }
    private func detectLlamaCLI() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(homeDir)/Library/Application Support/Lina/llama.cpp/build/bin/llama-cli",
            "\(homeDir)/Desktop/Lina/Lina/llama.cpp/build/bin/llama-cli",
        ]
        print("[LlamaCPP] Checking for app's own llama-cli installation...")
        print("[LlamaCPP] Home directory: \(homeDir)")
        for path in possiblePaths {
            print("[LlamaCPP] Checking: \(path)")
            if FileManager.default.fileExists(atPath: path) {
                print("[LlamaCPP] ✓ Found app's llama-cli at: \(path)")
                return path
            } else {
                print("[LlamaCPP] ✗ Not found at: \(path)")
            }
        }
        print("[LlamaCPP] App's llama-cli not found - installation required")
        return nil
    }
    private func shellCommand(_ command: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    return output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            print("[LlamaCPP] Shell command failed: \(error)")
        }
        return ""
    }
    private func getLlamaCLIPath() -> String {
        if let detectedPath = detectLlamaCLI() {
            return detectedPath
        }
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/Application Support/Lina/llama.cpp/build/bin/llama-cli"
    }
    private func getLlamaCPPDir() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/Application Support/Lina/llama.cpp"
    }
    func isLlamaCPPInstalled() -> Bool {
        return detectLlamaCLI() != nil
    }
    func installCMakeLocally(to appSupportPath: String) -> String? {
        let cmakeDir = "\(appSupportPath)/cmake"
        let cmakeBinPath = "\(cmakeDir)/bin/cmake"
        if FileManager.default.fileExists(atPath: cmakeBinPath) {
            print("[LlamaCPP] CMake already installed locally at: \(cmakeBinPath)")
            return cmakeBinPath
        }
        print("[LlamaCPP] Downloading CMake for macOS (no sudo required)...")
        let cmakeVersion = "3.27.7"
        let cmakeArch = "macos-universal"
        let cmakeURL = "https://github.com/Kitware/CMake/releases/download/v\(cmakeVersion)/cmake-\(cmakeVersion)-\(cmakeArch).tar.gz"
        let cmakeTarPath = "\(appSupportPath)/cmake.tar.gz"
        print("[LlamaCPP] Downloading from: \(cmakeURL)")
        guard let url = URL(string: cmakeURL) else {
            print("[LlamaCPP] Invalid CMake download URL")
            return nil
        }
        let semaphore = DispatchSemaphore(value: 0)
        var downloadSuccess = false
        let downloadTask = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            if let error = error {
                print("[LlamaCPP] CMake download error: \(error)")
                semaphore.signal()
                return
            }
            guard let tempURL = tempURL else {
                print("[LlamaCPP] No temp URL for CMake download")
                semaphore.signal()
                return
            }
            do {
                if FileManager.default.fileExists(atPath: cmakeTarPath) {
                    try FileManager.default.removeItem(atPath: cmakeTarPath)
                }
                try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: cmakeTarPath))
                downloadSuccess = true
                print("[LlamaCPP] ✓ CMake downloaded successfully")
            } catch {
                print("[LlamaCPP] Error saving CMake: \(error)")
            }
            semaphore.signal()
        }
        downloadTask.resume()
        semaphore.wait()
        guard downloadSuccess else {
            print("[LlamaCPP] CMake download failed")
            return nil
        }
        print("[LlamaCPP] Extracting CMake...")
        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extractProcess.arguments = ["-xzf", cmakeTarPath, "-C", appSupportPath]
        do {
            try extractProcess.run()
            extractProcess.waitUntilExit()
            if extractProcess.terminationStatus != 0 {
                print("[LlamaCPP] CMake extraction failed")
                return nil
            }
        } catch {
            print("[LlamaCPP] Error extracting CMake: \(error)")
            return nil
        }
        let extractedDir = "\(appSupportPath)/cmake-\(cmakeVersion)-\(cmakeArch)"
        do {
            if FileManager.default.fileExists(atPath: cmakeDir) {
                try FileManager.default.removeItem(atPath: cmakeDir)
            }
            let cmakeAppPath = "\(extractedDir)/CMake.app/Contents"
            if FileManager.default.fileExists(atPath: cmakeAppPath) {
                try FileManager.default.moveItem(atPath: cmakeAppPath, toPath: cmakeDir)
            } else {
                try FileManager.default.moveItem(atPath: extractedDir, toPath: cmakeDir)
            }
            try? FileManager.default.removeItem(atPath: cmakeTarPath)
            try? FileManager.default.removeItem(atPath: extractedDir)
            if FileManager.default.fileExists(atPath: cmakeBinPath) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cmakeBinPath)
                print("[LlamaCPP] ✓ CMake installed successfully at: \(cmakeBinPath)")
                return cmakeBinPath
            } else {
                print("[LlamaCPP] CMake binary not found at expected path: \(cmakeBinPath)")
                return nil
            }
        } catch {
            print("[LlamaCPP] Error moving CMake files: \(error)")
            return nil
        }
    }
    func installLlamaCPP(completion: @escaping (Bool, String?) -> Void) {
        guard !isInstallingLlamaCPP else {
            completion(false, "Installation already in progress")
            return
        }
        isInstallingLlamaCPP = true
        llamaCPPInstallProgress = 0.0
        processQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    self?.isInstallingLlamaCPP = false
                    completion(false, "Installation failed")
                }
                return
            }
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let appSupportPath = "\(homeDir)/Library/Application Support/Lina"
            let llamaCppPath = "\(appSupportPath)/llama.cpp"
            let buildPath = "\(llamaCppPath)/build"
            DispatchQueue.main.async {
                self.llamaCPPInstallProgress = 0.0
                self.llamaCPPInstallStatus = "Creating directories..."
            }
            do {
                try FileManager.default.createDirectory(atPath: appSupportPath, withIntermediateDirectories: true)
            } catch {
                print("[LlamaCPP] Failed to create app support directory: \(error)")
                DispatchQueue.main.async {
                    self.isInstallingLlamaCPP = false
                    completion(false, "Failed to create directory")
                }
                return
            }
            DispatchQueue.main.async {
                self.llamaCPPInstallProgress = 0.02
                self.llamaCPPInstallStatus = "Downloading llama.cpp..."
            }
            if FileManager.default.fileExists(atPath: llamaCppPath) {
                print("[LlamaCPP] Removing existing llama.cpp directory for clean install...")
                do {
                    try FileManager.default.removeItem(atPath: llamaCppPath)
                } catch {
                    print("[LlamaCPP] Warning: Could not remove existing directory: \(error)")
                }
            }
            let cloneProcess = Process()
            cloneProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            cloneProcess.arguments = ["clone", "--progress", "https://github.com/ggerganov/llama.cpp.git", llamaCppPath]
            cloneProcess.currentDirectoryURL = URL(fileURLWithPath: appSupportPath)
            let clonePipe = Pipe()
            cloneProcess.standardOutput = clonePipe
            cloneProcess.standardError = clonePipe
            print("[LlamaCPP] Starting FULL git clone (this will take 5-7 minutes)...")
            do {
                try cloneProcess.run()
                let cloneStartTime = Date()
                var lastGitOutputTime = Date()
                DispatchQueue.global(qos: .background).async {
                    while cloneProcess.isRunning {
                        let availableData = clonePipe.fileHandleForReading.availableData
                        if !availableData.isEmpty {
                            if let output = String(data: availableData, encoding: .utf8) {
                                print("[LlamaCPP] Git: \(output)", terminator: "")
                                if let percentMatch = output.range(of: #"(\d+)%"#, options: .regularExpression) {
                                    let percentStr = output[percentMatch].replacingOccurrences(of: "%", with: "")
                                    if let gitPercent = Double(percentStr) {
                                        var adjustedPercent = gitPercent
                                        if output.contains("Counting objects") {
                                            adjustedPercent = gitPercent * 0.1
                                        } else if output.contains("Compressing objects") {
                                            adjustedPercent = 10 + (gitPercent * 0.1)
                                        } else if output.contains("Receiving objects") {
                                            adjustedPercent = 20 + (gitPercent * 0.7)
                                        } else if output.contains("Resolving deltas") {
                                            adjustedPercent = 90 + (gitPercent * 0.1)
                                        }
                                        DispatchQueue.main.async {
                                            let cloneProgress = 0.02 + (adjustedPercent / 100.0) * 0.92
                                            if cloneProgress > self.llamaCPPInstallProgress {
                                                self.llamaCPPInstallProgress = cloneProgress
                                            }
                                        }
                                    }
                                }
                                lastGitOutputTime = Date()
                            }
                        }
                        let now = Date()
                        if now.timeIntervalSince(lastGitOutputTime) >= 3.0 {
                            DispatchQueue.main.async {
                                let elapsed = now.timeIntervalSince(cloneStartTime)
                                let estimatedProgress = min(0.94, 0.02 + (elapsed / 420.0) * 0.92)
                                if estimatedProgress > self.llamaCPPInstallProgress {
                                    self.llamaCPPInstallProgress = estimatedProgress
                                }
                            }
                            lastGitOutputTime = now
                        }
                        Thread.sleep(forTimeInterval: 0.5)
                    }
                }
                cloneProcess.waitUntilExit()
                let remainingData = clonePipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: remainingData, encoding: .utf8), !output.isEmpty {
                    print("[LlamaCPP] Git: \(output)")
                }
                if cloneProcess.terminationStatus != 0 {
                    print("[LlamaCPP] ✗ Git clone failed")
                    DispatchQueue.main.async {
                        self.isInstallingLlamaCPP = false
                        completion(false, "Clone failed. Check internet connection.")
                    }
                    return
                }
                print("[LlamaCPP] ✓ Git clone completed successfully!")
            } catch {
                print("[LlamaCPP] ✗ Error cloning repository: \(error)")
                DispatchQueue.main.async {
                    self.isInstallingLlamaCPP = false
                    completion(false, "Download failed")
                }
                return
            }
            DispatchQueue.main.async {
                self.llamaCPPInstallProgress = 0.94
                self.llamaCPPInstallStatus = "Clone complete! Checking for CMake..."
            }
            Thread.sleep(forTimeInterval: 0.5)
            let cmakeListsPath = "\(llamaCppPath)/CMakeLists.txt"
            let srcPath = "\(llamaCppPath)/src"
            guard FileManager.default.fileExists(atPath: cmakeListsPath),
                  FileManager.default.fileExists(atPath: srcPath) else {
                print("[LlamaCPP] ✗ Clone verification failed")
                DispatchQueue.main.async {
                    self.isInstallingLlamaCPP = false
                    completion(false, "Clone incomplete. Please retry.")
                }
                return
            }
            print("[LlamaCPP] ✓ Clone verification passed")
            let cmakePaths = [
                "/usr/local/bin/cmake",
                "/opt/homebrew/bin/cmake",
                "/usr/bin/cmake",
                "\(homeDir)/.local/bin/cmake",
                "/Applications/CMake.app/Contents/bin/cmake"
            ]
            var cmakePath: String? = nil
            for path in cmakePaths {
                if FileManager.default.fileExists(atPath: path) {
                    cmakePath = path
                    print("[LlamaCPP] Found CMake at: \(path)")
                    break
                }
            }
            if cmakePath == nil {
                let whichProcess = Process()
                whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                whichProcess.arguments = ["cmake"]
                let pipe = Pipe()
                whichProcess.standardOutput = pipe
                do {
                    try whichProcess.run()
                    whichProcess.waitUntilExit()
                    if whichProcess.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !path.isEmpty {
                            cmakePath = path
                        }
                    }
                } catch {}
            }
            var finalCmakePath: String
            if let foundCmakePath = cmakePath {
                finalCmakePath = foundCmakePath
            } else {
                print("[LlamaCPP] CMake not found. Installing locally...")
                DispatchQueue.main.async {
                    self.llamaCPPInstallProgress = 0.945
                    self.llamaCPPInstallStatus = "Installing CMake..."
                }
                if let installedPath = self.installCMakeLocally(to: appSupportPath) {
                    finalCmakePath = installedPath
                    print("[LlamaCPP] ✓ CMake installed locally")
                } else {
                    DispatchQueue.main.async {
                        self.isInstallingLlamaCPP = false
                        completion(false, "Failed to install CMake. Please install with: brew install cmake")
                    }
                    return
                }
            }
            DispatchQueue.main.async {
                self.llamaCPPInstallProgress = 0.95
                self.llamaCPPInstallStatus = "Configuring build with CMake..."
            }
            do {
                try FileManager.default.createDirectory(atPath: buildPath, withIntermediateDirectories: true)
            } catch {
                DispatchQueue.main.async {
                    self.isInstallingLlamaCPP = false
                    completion(false, "Failed to create build directory")
                }
                return
            }
            let configureProcess = Process()
            configureProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            configureProcess.currentDirectoryURL = URL(fileURLWithPath: buildPath)
            configureProcess.arguments = ["-c", "'\(finalCmakePath)' -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON .."]
            let errorPipe = Pipe()
            configureProcess.standardError = errorPipe
            configureProcess.standardOutput = errorPipe
            do {
                try configureProcess.run()
                configureProcess.waitUntilExit()
                if configureProcess.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.isInstallingLlamaCPP = false
                        completion(false, "CMake configuration failed")
                    }
                    return
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstallingLlamaCPP = false
                    completion(false, "CMake configuration error")
                }
                return
            }
            DispatchQueue.main.async {
                self.llamaCPPInstallProgress = 0.96
                self.llamaCPPInstallStatus = "Building llama.cpp..."
            }
            let buildProcess = Process()
            buildProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            buildProcess.currentDirectoryURL = URL(fileURLWithPath: buildPath)
            let cpuCount = ProcessInfo.processInfo.activeProcessorCount
            buildProcess.arguments = ["-c", "'\(finalCmakePath)' --build . --config Release -j \(cpuCount)"]
            let buildPipe = Pipe()
            buildProcess.standardOutput = buildPipe
            buildProcess.standardError = buildPipe
            do {
                try buildProcess.run()
                let buildStartTime = Date()
                DispatchQueue.global(qos: .background).async {
                    var lastBuildUpdate = Date()
                    while buildProcess.isRunning {
                        let availableData = buildPipe.fileHandleForReading.availableData
                        if !availableData.isEmpty {
                            if let output = String(data: availableData, encoding: .utf8) {
                                print("[LlamaCPP] Build: \(output)", terminator: "")
                                if let buildMatch = output.range(of: #"\[(\d+)/(\d+)\]"#, options: .regularExpression) {
                                    let buildStr = output[buildMatch]
                                    let numbers = buildStr.components(separatedBy: CharacterSet(charactersIn: "[]/ "))
                                        .compactMap { Int($0) }
                                    if numbers.count >= 2 {
                                        let current = Double(numbers[0])
                                        let total = Double(numbers[1])
                                        let buildPercent = current / total
                                        DispatchQueue.main.async {
                                            let progress = 0.96 + (buildPercent * 0.03)
                                            if progress > self.llamaCPPInstallProgress {
                                                self.llamaCPPInstallProgress = progress
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        let now = Date()
                        if now.timeIntervalSince(lastBuildUpdate) >= 3.0 {
                            DispatchQueue.main.async {
                                let elapsed = now.timeIntervalSince(buildStartTime)
                                let estimatedProgress = min(0.99, 0.96 + (elapsed / 300.0) * 0.03)
                                if estimatedProgress > self.llamaCPPInstallProgress {
                                    self.llamaCPPInstallProgress = estimatedProgress
                                }
                            }
                            lastBuildUpdate = now
                        }
                        Thread.sleep(forTimeInterval: 0.5)
                    }
                }
                buildProcess.waitUntilExit()
                if buildProcess.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.isInstallingLlamaCPP = false
                        completion(false, "Build failed")
                    }
                    return
                }
                let mainExecutable = "\(buildPath)/bin/llama-cli"
                let targetPath = "\(llamaCppPath)/main"
                if FileManager.default.fileExists(atPath: mainExecutable) {
                    try? FileManager.default.removeItem(atPath: targetPath)
                    try? FileManager.default.copyItem(atPath: mainExecutable, toPath: targetPath)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetPath)
                }
                DispatchQueue.main.async {
                    self.llamaCPPInstallProgress = 0.99
                    self.llamaCPPInstallStatus = "Finalizing installation..."
                }
                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.async {
                    self.llamaCPPInstallProgress = 1.0
                    self.llamaCPPInstallStatus = "Installation complete!"
                    self.isInstallingLlamaCPP = false
                    completion(true, nil)
                    print("[LlamaCPP] ✓ Installation completed successfully")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstallingLlamaCPP = false
                    completion(false, "Build error")
                }
            }
        }
    }
    func generateResponse(
        prompt: String,
        sessionId: UUID,
        conversationHistory: [ChatMessage] = [],
        isTerminalMode: Bool = false,
        onToken: ((String) -> Void)? = nil,
        onComplete: @escaping (String) -> Void
    ) {
        guard isModelLoaded, let model = currentModel else {
            DispatchQueue.main.async {
                onComplete("Error: No model loaded")
            }
            return
        }
        guard !isGenerating else {
            DispatchQueue.main.async {
                onComplete("Error: Already generating")
            }
            return
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DispatchQueue.main.async {
                onComplete("Error: Empty prompt")
            }
            return
        }
        print("[LlamaCPP] Starting generation for: \(prompt)")
        DispatchQueue.main.async {
            self.isGenerating = true
        }
        streamingBuffer = ""
        tokenCount = 0
        lastTokenTime = Date()
        let contextMessages = conversationHistory
        var fullPrompt = ""
        print("[LlamaCPP] Session ID: \(sessionId.uuidString.prefix(8))")
        print("[LlamaCPP] Using \(contextMessages.count) messages - llama.cpp manages context")
        if !contextMessages.isEmpty {
            print("[LlamaCPP] Context messages:")
            for (index, message) in contextMessages.enumerated() {
                let preview = message.content.prefix(50)
                print("[LlamaCPP]   \(index + 1). \(message.isFromUser ? "User" : "Assistant"): \(preview)...")
                if message.isFromUser {
                    fullPrompt += "User: \(message.content)"
                    
                    if let attachedFiles = message.attachedFiles, !attachedFiles.isEmpty {
                        fullPrompt += "\n\n[Attached Files]:\n"
                        for file in attachedFiles {
                            let fileURL = URL(fileURLWithPath: file.filePath)
                            if fileURL.startAccessingSecurityScopedResource() {
                                defer { fileURL.stopAccessingSecurityScopedResource() }
                                
                                fullPrompt += "\n--- File: \(file.fileName) (Type: \(file.fileType)) ---\n"
                                
                                do {
                                    let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                                    fullPrompt += fileContent
                                    print("[LlamaCPP] Successfully read file: \(file.fileName) (\(fileContent.count) characters)")
                                } catch let error as NSError {
                                    if error.domain == NSCocoaErrorDomain && error.code == 261 {
                                        if let data = try? Data(contentsOf: fileURL),
                                           let content = String(data: data, encoding: .utf8) {
                                            fullPrompt += content
                                            print("[LlamaCPP] Read file with fallback: \(file.fileName)")
                                        } else {
                                            fullPrompt += "[Unable to read file as text]"
                                            print("[LlamaCPP] Could not read file as text: \(file.fileName)")
                                        }
                                    } else {
                                        fullPrompt += "[Error reading file: \(error.localizedDescription)]"
                                        print("[LlamaCPP] Error reading file \(file.fileName): \(error)")
                                    }
                                }
                                
                                fullPrompt += "\n--- End of \(file.fileName) ---\n"
                            } else {
                                fullPrompt += "\n[Could not access file: \(file.fileName)]\n"
                                print("[LlamaCPP] Security-scoped access denied for: \(file.fileName)")
                            }
                        }
                    }
                    
                    fullPrompt += "\n\n"
                } else {
                    fullPrompt += "Assistant: \(message.content)\n\n"
                }
            }
        } else {
            print("[LlamaCPP] WARNING: No conversation history - starting fresh")
        }
        fullPrompt += "User: \(prompt)\n\nAssistant:"
        print("[LlamaCPP] Final prompt length: \(fullPrompt.count) characters")
        print("[LlamaCPP] Full prompt preview:")
        print("[LlamaCPP] ---")
        print(fullPrompt.prefix(500))
        if fullPrompt.count > 500 {
            print("[LlamaCPP] ... (\(fullPrompt.count - 500) more characters)")
        }
        print("[LlamaCPP] ---")
        print("[LlamaCPP] ============================================")
        processQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            let llamaCLIPath = strongSelf.getLlamaCLIPath()
            let modelPath = model.filePath
            guard FileManager.default.fileExists(atPath: llamaCLIPath) else {
                DispatchQueue.main.async {
                    strongSelf.isGenerating = false
                    onComplete("Error: llama.cpp not installed")
                }
                return
            }
            guard FileManager.default.fileExists(atPath: modelPath) else {
                DispatchQueue.main.async {
                    strongSelf.isGenerating = false
                    onComplete("Error: Model file not found")
                }
                return
            }
            do {
                let process = Process()
                strongSelf.sessionLock.lock()
                strongSelf.sessionProcesses[sessionId] = process
                strongSelf.currentProcess = process
                strongSelf.sessionLock.unlock()
                print("[LlamaCPP] Created dedicated llama.cpp process for session: \(sessionId.uuidString.prefix(8))")
                print("[LlamaCPP] Active session processes: \(strongSelf.sessionProcesses.count)")
                process.executableURL = URL(fileURLWithPath: llamaCLIPath)
                process.arguments = [
                    "-m", modelPath,
                    "-p", fullPrompt,
                    "-n", String(strongSelf.defaultMaxTokens),
                    "-c", String(strongSelf.defaultContextLength),
                    "--temp", String(strongSelf.defaultTemperature),
                    "--top-k", String(strongSelf.defaultTopK),
                    "--top-p", String(strongSelf.defaultTopP),
                    "--repeat-penalty", String(strongSelf.defaultRepeatPenalty),
                    "--repeat-last-n", String(strongSelf.defaultRepeatLastN),
                    "-ngl", "99",  // Offload all layers to GPU if available
                    "--no-display-prompt",
                    "--simple-io"  // Use simple I/O for better streaming
                ]
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                let inputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                process.standardInput = inputPipe
                try process.run()
                try? inputPipe.fileHandleForWriting.close()
                var accumulatedResponse = ""
                if let onToken = onToken {
                    let outputQueue = DispatchQueue(label: "com.lina.output", qos: .userInteractive)
                    outputQueue.async {
                        let handle = outputPipe.fileHandleForReading
                        var buffer = Data()
                        while process.isRunning {
                            autoreleasepool {
                                let availableData = handle.availableData
                                if !availableData.isEmpty {
                                    buffer.append(availableData)
                                    if let text = String(data: buffer, encoding: .utf8) {
                                        if !text.isEmpty {
                                            accumulatedResponse += text
                                            DispatchQueue.main.async {
                                                onToken(text)
                                            }
                                        }
                                        buffer.removeAll()
                                    } else if buffer.count > 4 {
                                        var validLength = 0
                                        for i in (0..<buffer.count).reversed() {
                                            if let partial = String(data: buffer.prefix(i), encoding: .utf8) {
                                                validLength = i
                                                if !partial.isEmpty {
                                                    accumulatedResponse += partial
                                                    DispatchQueue.main.async {
                                                        onToken(partial)
                                                    }
                                                }
                                                break
                                            }
                                        }
                                        if validLength > 0 {
                                            buffer.removeFirst(validLength)
                                        }
                                    }
                                }
                               usleep(1000) // 1ms polling interval for instant streaming
                            }
                        }
                    }
                }
                process.waitUntilExit()
                if onToken == nil {
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let text = String(data: outputData, encoding: .utf8) {
                        accumulatedResponse = text
                    }
                }
                var cleanedResponse = accumulatedResponse
                print("[LlamaCPP] Raw response length: \(accumulatedResponse.count) characters")
                print("[LlamaCPP] Raw response preview: \(accumulatedResponse.prefix(200))...")
                if cleanedResponse.hasPrefix("User:") {
                    if let assistantRange = cleanedResponse.range(of: "\n\nAssistant:", options: .caseInsensitive) {
                        cleanedResponse = String(cleanedResponse[assistantRange.upperBound...])
                    } else if let aRange = cleanedResponse.range(of: "\n\nA:") {
                        cleanedResponse = String(cleanedResponse[aRange.upperBound...])
                    }
                }
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "\n\n>", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "\n>", with: "")
                if cleanedResponse.hasSuffix(">") {
                    cleanedResponse = String(cleanedResponse.dropLast(1))
                }
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "EOF", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "[end of text]", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "<|endoftext|>", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "<|end|>", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "<|eot_id|>", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "</s>", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "<|im_end|>", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "\n  >", with: "")
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "  >", with: "")
                if cleanedResponse.hasPrefix("\nUser:") {
                    cleanedResponse = String(cleanedResponse.dropFirst(6))
                }
                if cleanedResponse.hasPrefix("\nAssistant:") {
                    cleanedResponse = String(cleanedResponse.dropFirst(12))
                }
                if cleanedResponse.hasPrefix("User:") {
                    cleanedResponse = String(cleanedResponse.dropFirst(5))
                }
                if cleanedResponse.hasPrefix("Assistant:") {
                    cleanedResponse = String(cleanedResponse.dropFirst(10))
                }
                if cleanedResponse.hasSuffix("\nUser:") {
                    cleanedResponse = String(cleanedResponse.dropLast(6))
                }
                if cleanedResponse.hasSuffix("\nAssistant:") {
                    cleanedResponse = String(cleanedResponse.dropLast(12))
                }
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "by user", with: "", options: .caseInsensitive)
                cleanedResponse = cleanedResponse.replacingOccurrences(of: "by the user", with: "", options: .caseInsensitive)
                cleanedResponse = cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                while cleanedResponse.contains("\n\n\n") {
                    cleanedResponse = cleanedResponse.replacingOccurrences(of: "\n\n\n", with: "\n\n")
                }
                let lines = cleanedResponse.components(separatedBy: "\n")
                var processedLines: [String] = []
                var inCodeBlock = false
                for line in lines {
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        inCodeBlock.toggle()
                        processedLines.append(line)
                        continue
                    }
                    if inCodeBlock {
                        processedLines.append(line)
                    } else {
                        var processedLine = line
                        while processedLine.contains("  ") {
                            processedLine = processedLine.replacingOccurrences(of: "  ", with: " ")
                        }
                        processedLines.append(processedLine)
                    }
                }
                cleanedResponse = processedLines.joined(separator: "\n")
                let finalResponse = cleanedResponse
                print("[LlamaCPP] Cleaned response length: \(finalResponse.count) characters")
                print("[LlamaCPP] Response preview: \(finalResponse.prefix(100))...")
                strongSelf.sessionLock.lock()
                strongSelf.sessionProcesses.removeValue(forKey: sessionId)
                strongSelf.currentProcess = nil
                strongSelf.sessionLock.unlock()
                print("[LlamaCPP] Closed llama.cpp process for session: \(sessionId.uuidString.prefix(8))")
                print("[LlamaCPP] Remaining active session processes: \(strongSelf.sessionProcesses.count)")
                DispatchQueue.main.async {
                    strongSelf.isGenerating = false
                    onComplete(finalResponse.isEmpty ? "Generating stopped by user." : finalResponse)
                }
                print("[LlamaCPP] Generation completed successfully")
            } catch {
                DispatchQueue.main.async {
                    strongSelf.isGenerating = false
                    onComplete("Error: \(error.localizedDescription)")
                }
            }
        }
    }
    func generateResponse(for prompt: String, completion: @escaping (String) -> Void) {
        let tempSessionId = UUID()
        generateResponse(
            prompt: prompt,
            sessionId: tempSessionId,
            conversationHistory: [],
            onToken: nil,
            onComplete: completion
        )
    }
}
