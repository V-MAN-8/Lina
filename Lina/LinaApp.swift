import SwiftUI
@main
struct LinaApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .accentColor(.gray)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
class AppState: ObservableObject {
    @Published var isFirstLaunch: Bool
    @Published var hasDownloadedModels: Bool
    @Published var currentView: AppView = .welcome
    @Published var downloadedModels: [AIModel] = []
    @Published var selectedModel: AIModel?
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatSessions: [ChatSession] = []
    @Published var currentSession: ChatSession?
    init() {
        let hasDownloaded = UserDefaults.standard.bool(forKey: "hasDownloadedModels")
        self.hasDownloadedModels = hasDownloaded
        self.isFirstLaunch = !hasDownloaded
        loadDownloadedModels()
        loadChatSessions()
        if hasDownloaded {
            self.currentView = .chat
        }
        ModelDownloadManager.shared.resumeIncompleteDownloads(models: downloadedModels)
        checkAndInstallLlamaCPP()
    }
    private func checkAndInstallLlamaCPP() {
        let isInstalled = LlamaCPPManager.shared.isLlamaCPPInstalled()
        if isInstalled {
            print("[AppState] llama.cpp is already installed")
            return
        }
        print("[AppState] llama.cpp not found - starting installation...")
        DispatchQueue.main.async {
            LlamaCPPManager.shared.installLlamaCPP { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("[AppState] llama.cpp installation completed successfully")
                    } else {
                        print("[AppState] llama.cpp installation failed: \(error ?? "Unknown error")")
                    }
                }
            }
        }
    }
    func addModel(_ model: AIModel) {
        downloadedModels.append(model)
        hasDownloadedModels = true
        UserDefaults.standard.set(true, forKey: "hasDownloadedModels")
        saveModels()
        if model.isDownloaded && !model.filePath.isEmpty {
            DispatchQueue.global(qos: .background).async {
                _ = LlamaCPPManager.shared.extractChatTemplateForModel(modelPath: model.filePath)
            }
        }
        if selectedModel == nil && model.isDownloaded {
            selectModel(model)
        }
        if isFirstLaunch {
            currentView = .chat
            isFirstLaunch = false
        }
    }
    func updateModelProgress(_ modelId: UUID, progress: Double, downloadedBytes: Int64, totalBytes: Int64, downloadSpeed: Double = 0.0) {
        if let index = downloadedModels.firstIndex(where: { $0.id == modelId }) {
            downloadedModels[index].downloadProgress = progress
            downloadedModels[index].downloadedBytes = downloadedBytes
            downloadedModels[index].totalBytes = totalBytes
            downloadedModels[index].downloadSpeed = downloadSpeed
            saveModels() // Save progress updates
        }
    }
    func completeModelDownload(_ modelId: UUID, filePath: String) {
        if let index = downloadedModels.firstIndex(where: { $0.id == modelId }) {
            downloadedModels[index].isDownloaded = true
            downloadedModels[index].downloadProgress = 1.0
            downloadedModels[index].filePath = filePath
            let fileSize = FileManagerUtility.shared.getModelFileSize(downloadedModels[index])
            if fileSize > 0 {
                downloadedModels[index].size = FileManagerUtility.shared.formatFileSize(fileSize)
            }
            saveModels()
            if selectedModel == nil {
                selectModel(downloadedModels[index])
            }
        }
    }
    func selectModel(_ model: AIModel) {
        selectedModel = model
        saveSelectedModel()
        LlamaCPPManager.shared.loadModel(model)
    }
    func deleteModel(_ model: AIModel) {
        print("[ModelPersistence] Deleting model: \(model.name)")
        downloadedModels.removeAll { $0.id == model.id }
        if selectedModel?.id == model.id {
            selectedModel = nil
            UserDefaults.standard.removeObject(forKey: "selectedModelId")
        }
        saveModels()
        if downloadedModels.isEmpty {
            hasDownloadedModels = false
            UserDefaults.standard.set(false, forKey: "hasDownloadedModels")
        }
        print("[ModelPersistence] Model deleted. Remaining models: \(downloadedModels.count)")
    }
    func clearAllModels() {
        print("[ModelPersistence] Clearing ALL saved models from UserDefaults")
        downloadedModels.removeAll()
        selectedModel = nil
        UserDefaults.standard.removeObject(forKey: "downloadedModels")
        UserDefaults.standard.removeObject(forKey: "selectedModelId")
        UserDefaults.standard.set(false, forKey: "hasDownloadedModels")
        UserDefaults.standard.synchronize()
        hasDownloadedModels = false
        print("[ModelPersistence] All models cleared")
    }
    func newChat() {
        let session = ChatSession(id: UUID(), title: "New Chat", messages: [], createdAt: Date())
        chatSessions.insert(session, at: 0)
        currentSession = session
        chatMessages = []
        saveChatSessions()
        if currentView != .chat {
            currentView = .chat
        }
    }
    func updateChatTitle(from message: String) {
        guard let currentSession = currentSession else { return }
        if currentSession.title == "New Chat" {
            let words = message.split(separator: " ").prefix(8)
            let titleWords = words.prefix(min(8, max(4, words.count)))
            var newTitle = titleWords.joined(separator: " ")
            if words.count > 8 {
                newTitle += "..."
            }
            if let index = chatSessions.firstIndex(where: { $0.id == currentSession.id }) {
                chatSessions[index].title = newTitle.isEmpty ? "New Chat" : newTitle
                self.currentSession = chatSessions[index]
                saveChatSessions() // Save updated title
            }
        }
    }
    func addMessage(_ message: ChatMessage) {
        chatMessages.append(message)
        if let currentSession = currentSession {
            if let index = chatSessions.firstIndex(where: { $0.id == currentSession.id }) {
                chatSessions[index].messages.append(message)
                chatSessions[index].messages = chatMessages // Sync all messages
                saveChatSessions() // Save after each message
            }
        }
        if message.isFromUser && chatMessages.filter({ $0.isFromUser }).count == 1 {
            updateChatTitle(from: message.content)
        }
    }
    private func loadDownloadedModels() {
        print("[ModelPersistence] Attempting to load saved models from UserDefaults")
        guard let data = UserDefaults.standard.data(forKey: "downloadedModels") else {
            print("[ModelPersistence] No saved models found - first launch")
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let savedModels = try decoder.decode([AIModel].self, from: data)
            downloadedModels = savedModels
            print("[ModelPersistence] Successfully loaded \(savedModels.count) models")
            if let selectedId = UserDefaults.standard.string(forKey: "selectedModelId"),
               let uuid = UUID(uuidString: selectedId),
               let model = downloadedModels.first(where: { $0.id == uuid && $0.isDownloaded }) {
                selectedModel = model
                LlamaCPPManager.shared.loadModel(model)
                print("[ModelPersistence] Auto-loaded selected model: \(model.name)")
            } else if let firstModel = downloadedModels.first(where: { $0.isDownloaded }) {
                print("[ModelPersistence] No previously selected model, using first available: \(firstModel.name)")
                selectModel(firstModel)
            }
        } catch {
            print("[ModelPersistence] Error: Failed to decode saved models - \(error)")
            print("[ModelPersistence] Data size: \(data.count) bytes")
        }
    }
    func saveModels() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(downloadedModels)
            UserDefaults.standard.set(data, forKey: "downloadedModels")
            UserDefaults.standard.synchronize()
            print("[ModelPersistence] Saved \(downloadedModels.count) models to UserDefaults")
        } catch {
            print("[ModelPersistence] Error: Failed to save models - \(error)")
        }
    }
    func saveSelectedModel() {
        if let selectedId = selectedModel?.id {
            UserDefaults.standard.set(selectedId.uuidString, forKey: "selectedModelId")
            UserDefaults.standard.synchronize()
            print("[ModelPersistence] Saved selected model ID: \(selectedId)")
        }
    }
    func saveChatSessions() {
        if let data = try? JSONEncoder().encode(chatSessions) {
            UserDefaults.standard.set(data, forKey: "savedChatSessions")
        }
    }
    private func loadChatSessions() {
        if let data = UserDefaults.standard.data(forKey: "savedChatSessions"),
           let savedSessions = try? JSONDecoder().decode([ChatSession].self, from: data) {
            chatSessions = savedSessions
            if let mostRecent = chatSessions.first {
                currentSession = mostRecent
                chatMessages = mostRecent.messages
            }
        }
    }
    func clearAllSessions() {
        chatSessions.removeAll()
        currentSession = nil
        chatMessages = []
        saveChatSessions()
    }
    func switchToSession(_ session: ChatSession) {
        currentSession = session
        chatMessages = session.messages
    }
}
enum AppView {
    case welcome
    case chat
    case models
}
struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt
    }
}
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var llamaManager = LlamaCPPManager.shared
    @State private var isSidebarVisible = true
    var body: some View {
        if llamaManager.isInstallingLlamaCPP {
            LlamaCPPInstallationView()
        } else if appState.currentView == .welcome {
            WelcomeView()
        } else {
            HStack(spacing: 0) {
                if isSidebarVisible {
                    ChatHistorySidebar()
                        .frame(width: 280)
                        .transition(.move(edge: .leading))
                }
                MainContentArea(isSidebarVisible: $isSidebarVisible)
                    .frame(maxWidth: .infinity)
            }
            .background(Color.black)
        }
    }
}
struct LlamaCPPInstallationView: View {
    @ObservedObject var llamaManager = LlamaCPPManager.shared
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 30) {
                Image(systemName: "cpu")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                Text("Installing llama.cpp")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text(llamaManager.llamaCPPInstallStatus.isEmpty ? "Preparing installation..." : llamaManager.llamaCPPInstallStatus)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.7))
                VStack(spacing: 10) {
                    ProgressView(value: llamaManager.llamaCPPInstallProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(width: 300)
                    Text("\(Int(llamaManager.llamaCPPInstallProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Text("This may take 10-15 minutes on first launch")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 20)
            }
        }
    }
}
struct ChatHistorySidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var isNewChatButtonHovered = false
    @FocusState private var isSearchFocused: Bool
    @State private var allowSearchFocus = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Chats")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        appState.newChat()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isNewChatButtonHovered ? .blue : .white.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(Color(white: 0.05))
                            .cornerRadius(8)
                            .scaleEffect(isNewChatButtonHovered ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isNewChatButtonHovered)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .onHover { hovering in
                        isNewChatButtonHovered = hovering
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.black)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.system(size: 14))
                TextField("Search chats...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                    .disabled(!allowSearchFocus)
                    .onTapGesture {
                        allowSearchFocus = true
                        isSearchFocused = true
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                allowSearchFocus = true
                isSearchFocused = true
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredSessions) { session in
                        ChatSessionRow(session: session, isSelected: appState.currentSession?.id == session.id)
                            .onTapGesture {
                                appState.switchToSession(session)
                                if appState.currentView != .chat {
                                    appState.currentView = .chat
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
    var filteredSessions: [ChatSession] {
        if searchText.isEmpty {
            return appState.chatSessions
        }
        return appState.chatSessions.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
}
struct ChatSessionRow: View {
    let session: ChatSession
    let isSelected: Bool
    @EnvironmentObject var appState: AppState
    @State private var isRowHovered = false
    @State private var isMenuHovered = false
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button(role: .destructive) {
                    deleteChat()
                } label: {
                    Label("Delete Chat", systemImage: "trash")
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(isMenuHovered ? 0.4 : 0.2), lineWidth: 1)
                        .background(Circle().fill(Color.clear))
                        .frame(width: 24, height: 24)
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white.opacity(isMenuHovered ? 0.8 : 0.6))
                        .font(.system(size: 12, weight: .medium))
                }
                .scaleEffect(isMenuHovered ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isMenuHovered)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .onHover { hovering in
                isMenuHovered = hovering
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.white.opacity(0.07) : (isRowHovered ? Color(red: 7/255, green: 31/255, blue: 51/255) : Color.clear))
        .cornerRadius(8)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isRowHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isRowHovered = hovering
        }
    }
    private func deleteChat() {
        if let index = appState.chatSessions.firstIndex(where: { $0.id == session.id }) {
            appState.chatSessions.remove(at: index)
            if appState.currentSession?.id == session.id {
                appState.currentSession = nil
                appState.chatMessages = []
            }
            appState.saveChatSessions()
        }
    }
}
struct ModelSelectorPopupView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showingMenu: Bool
    @Binding var showingModelPicker: Bool
    @State private var hoveredModel: UUID? = nil
    var body: some View {
        VStack(spacing: 0) {
            if appState.downloadedModels.isEmpty {
                Button(action: {}) {
                    HStack(spacing: 8) {
                        Text("No models available")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(true)
            } else {
                ForEach(appState.downloadedModels.filter { $0.isDownloaded }) { model in
                    Button(action: {
                        showingMenu = false
                        appState.selectModel(model)
                    }) {
                        HStack(spacing: 8) {
                            Text(model.name)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            if appState.selectedModel?.id == model.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(hoveredModel == model.id ? Color.blue.opacity(0.05) : Color.clear)
                    .onHover { hovering in
                        hoveredModel = hovering ? model.id : nil
                    }
                }
            }
            Divider()
                .background(Color.white.opacity(0.1))
            Button(action: {
                showingMenu = false
                showingModelPicker = true
            }) {
                HStack(spacing: 8) {
                    Text("Add New Model...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(hoveredModel == UUID(uuidString: "00000000-0000-0000-0000-000000000000") ? Color.blue.opacity(0.05) : Color.clear)
            .onHover { hovering in
                hoveredModel = hovering ? UUID(uuidString: "00000000-0000-0000-0000-000000000000") : nil
            }
        }
    }
}
struct MainContentArea: View {
    @EnvironmentObject var appState: AppState
    @Binding var isSidebarVisible: Bool
    @State private var isChatButtonHovered = false
    @State private var isModelsButtonHovered = false
    @State private var showingModelPicker = false
    @State private var isAddModelButtonHovered = false
    @State private var isHideSidebarButtonHovered = false
    @State private var isModelSelectorHovered = false
    @State private var showingModelMenu = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSidebarVisible.toggle()
                        }
                    }) {
                        Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isHideSidebarButtonHovered ? .blue : .gray)
                            .frame(width: 20, height: 20)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .scaleEffect(isHideSidebarButtonHovered ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isHideSidebarButtonHovered)
                    .onHover { hovering in
                        isHideSidebarButtonHovered = hovering
                    }
                    Button(action: {
                        appState.currentView = .chat
                    }) {
                        Text("Chat")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isChatButtonHovered ? .blue : .gray)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .scaleEffect(isChatButtonHovered ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isChatButtonHovered)
                    .onHover { hovering in
                        isChatButtonHovered = hovering
                    }
                    Button(action: {
                        appState.currentView = .models
                    }) {
                        Text("Models")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isModelsButtonHovered ? .blue : .gray)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .scaleEffect(isModelsButtonHovered ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isModelsButtonHovered)
                    .onHover { hovering in
                        isModelsButtonHovered = hovering
                    }
                }
                .padding(.leading, 16)
                Spacer()
                if appState.currentView == .models {
                    HStack(spacing: 0) {
                        Button(action: {
                            showingModelPicker = true
                        }) {
                            Text("Add Model")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isAddModelButtonHovered ? .blue : .gray)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .scaleEffect(isAddModelButtonHovered ? 1.05 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isAddModelButtonHovered)
                        .onHover { hovering in
                            isAddModelButtonHovered = hovering
                        }
                    }
                    .offset(y: -4)
                    .padding(.trailing, 16)
                }
                if appState.currentView == .chat {
                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                showingModelMenu.toggle()
                            }
                        }) {
                            HStack(spacing: 8) {
                                if let model = appState.selectedModel {
                                    Text(model.name)
                                        .lineLimit(1)
                                } else {
                                    Text("Select Model")
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isModelSelectorHovered ? .blue : .gray)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .scaleEffect(isModelSelectorHovered ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: isModelSelectorHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isModelSelectorHovered = hovering
                        }
                        .background(
                            Group {
                                if showingModelMenu {
                                    Color.clear
                                        .frame(width: 0, height: 0)
                                        .popover(isPresented: $showingModelMenu, arrowEdge: .bottom) {
                                            ModelSelectorPopupView(
                                                showingMenu: $showingModelMenu,
                                                showingModelPicker: $showingModelPicker
                                            )
                                            .environmentObject(appState)
                                        }
                                }
                            }
                        )
                    }
                    .offset(y: -4)
                    .padding(.trailing, 16)
                }
            }
            .padding(.vertical, 12)
            .background(Color.black)
            .zIndex(1)
            ZStack {
                switch appState.currentView {
                case .chat:
                    ChatView()
                case .models:
                    ModelsView()
                case .welcome:
                    EmptyView()
                }
            }
        }
        .background(Color.black)
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView()
                .frame(width: 600, height: 500)
        }
    }
}
#Preview {
    ContentView()
        .environmentObject(AppState())
}
