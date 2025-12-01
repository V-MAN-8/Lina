import SwiftUI
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var hasScrolledToBottom = false
    @FocusState private var isMessageFieldFocused: Bool
    @State private var isSelectModelButtonHovered = false
    @State private var isSendButtonHovered = false
    @State private var isAttachButtonHovered = false
    @State private var showingFilePicker = false
    @State private var attachedFiles: [URL] = []
    @State private var hasAppearedOnce = false
    @State private var showingNoModelAlert = false
    @State private var sessionTypingState: [UUID: Bool] = [:]
    @State private var sessionStreamingId: [UUID: UUID] = [:]
    @State private var sessionStreamingContent: [UUID: String] = [:]
    private var isTyping: Bool {
        guard let sessionId = appState.currentSession?.id else { return false }
        return sessionTypingState[sessionId] ?? false
    }
    private var streamingMessageId: UUID? {
        guard let sessionId = appState.currentSession?.id else { return nil }
        return sessionStreamingId[sessionId]
    }
    private var streamingContent: String {
        guard let sessionId = appState.currentSession?.id else { return "" }
        return sessionStreamingContent[sessionId] ?? ""
    }
    var body: some View {
        VStack(spacing: 0) {
            if appState.chatMessages.isEmpty && !isTyping {
                VStack(spacing: 0) {
                    Spacer()
                    Spacer()
                        .frame(height: 0)
                    VStack(spacing: 30) {
                        VStack(spacing: 20) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .opacity(0.8)
                            VStack(spacing: 8) {
                                Text("How can I help you today ?")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        HStack(alignment: .bottom, spacing: 12) {
                            Button(action: {
                                showingFilePicker = true
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(isAttachButtonHovered ? Color.blue : Color.blue.opacity(0.8))
                                }
                                .scaleEffect(isAttachButtonHovered ? 1.1 : 1)
                                .animation(.easeInOut(duration: 0.2), value: isAttachButtonHovered)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isAttachButtonHovered = hovering
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                if !attachedFiles.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(attachedFiles, id: \.self) { fileURL in
                                                FileCardView(fileURL: fileURL) {
                                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                        removeFile(fileURL)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                    }
                                    .frame(height: 86)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)
                                    ))
                                }
                                ZStack(alignment: .leading) {
                                    if messageText.isEmpty && attachedFiles.isEmpty {
                                        Text("Send a message")
                                            .foregroundColor(.white.opacity(0.5))
                                            .padding(.leading, 14)
                                    }
                                    TextField("", text: $messageText)
                                        .textFieldStyle(.plain)
                                        .foregroundColor(.white)
                                        .font(.system(size: 15))
                                        .padding(12)
                                        .focused($isMessageFieldFocused)
                                        .onSubmit {
                                            sendMessage()
                                        }
                                }
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: attachedFiles.count)
                            .background(Color(white: 0.12))
                            .cornerRadius(12)
                            ZStack {
                                Button(action: {
                                    sendMessage()
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.2))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "arrow.up")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(isSendButtonHovered ? Color.blue : Color.blue.opacity(0.8))
                                    }
                                    .scaleEffect(isSendButtonHovered ? 1.1 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: isSendButtonHovered)
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    isSendButtonHovered = hovering
                                }
                            }
                        }
                        .frame(maxWidth: 700)
                        .padding(.horizontal, 20)
                    }
                    Spacer()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            ForEach(appState.chatMessages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                            if isTyping, let streamingId = streamingMessageId {
                                if streamingContent.isEmpty {
                                    TypingIndicatorView()
                                        .id(streamingId)
                                } else {
                                    MessageBubbleView(message: ChatMessage(
                                        id: streamingId,
                                        content: streamingContent,
                                        isFromUser: false
                                    ))
                                    .id(streamingId)
                                }
                            }
                        }
                        .padding(20)
                        .padding(.bottom, attachedFiles.isEmpty ? 20 : 120) // Extra padding when files are attached
                    }
                    .background(Color.black)
                    .onAppear {
                        if !hasScrolledToBottom && !appState.chatMessages.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToBottom(proxy: proxy, animated: true)
                                hasScrolledToBottom = true
                            }
                        }
                    }
                    .onChange(of: appState.chatMessages.count) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: streamingContent) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: isTyping) { newValue in
                        if newValue {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: appState.currentSession?.id) { newSessionId in
                        hasScrolledToBottom = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isMessageFieldFocused = true
                        }
                        DispatchQueue.main.async {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToBottom(proxy: proxy, animated: false)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                scrollToBottom(proxy: proxy, animated: true)
                                hasScrolledToBottom = true
                            }
                        }
                    }
                }
            }
            if !appState.chatMessages.isEmpty || isTyping {
                HStack(alignment: .bottom, spacing: 12) {
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 32, height: 32)
                            Image(systemName: "paperclip")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isAttachButtonHovered ? Color.blue : Color.blue.opacity(0.8))
                        }
                        .scaleEffect(isAttachButtonHovered ? 1.1 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isAttachButtonHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isAttachButtonHovered = hovering
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if !attachedFiles.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(attachedFiles, id: \.self) { fileURL in
                                        FileCardView(fileURL: fileURL) {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                removeFile(fileURL)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                            }
                            .frame(height: 86)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            ))
                        }
                        ZStack(alignment: .leading) {
                            if messageText.isEmpty && attachedFiles.isEmpty {
                                Text("Send a message")
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.leading, 14)
                            }
                            TextField("", text: $messageText)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .foregroundColor(.white)
                                .accentColor(.gray)
                                .focused($isMessageFieldFocused)
                                .onSubmit {
                                    sendMessage()
                                }
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: attachedFiles.count)
                    .background(Color(white: 0.12))
                    .cornerRadius(12)
                    ZStack {
                        Button(action: {
                            if isTyping {
                                stopGeneration()
                            } else {
                                sendMessage()
                            }
                        }) {
                            ZStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(isSendButtonHovered ? Color.blue : Color.blue.opacity(0.8))
                                }
                                .opacity(isTyping ? 1 : 0)
                                .scaleEffect(isTyping ? (isSendButtonHovered ? 1.1 : 1) : 0.5)
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(isSendButtonHovered ? Color.blue : Color.blue.opacity(0.8))
                                }
                                .opacity(isTyping ? 0 : 1)
                                .scaleEffect(isTyping ? 0.5 : (isSendButtonHovered ? 1.1 : 1))
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTyping)
                            .animation(.easeInOut(duration: 0.2), value: isSendButtonHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isSendButtonHovered = hovering
                        }
                    }
                }
                .frame(maxWidth: 800)
                .padding(18)
                .background(Color.black)
            }
        }
        .background(Color.black)
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            isMessageFieldFocused = true
        }
        .alert("No Model Selected", isPresented: $showingNoModelAlert) {
            Button("Go to Models", role: .none) {
                appState.currentView = .models
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You need to install a model first. You can look in the model library for suggested models.")
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .text, .plainText, .image, .movie, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    for url in urls {
                        if url.startAccessingSecurityScopedResource() {
                            attachedFiles.append(url)
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isMessageFieldFocused = true
                }
            case .failure(let error):
                print("File picker error: \(error.localizedDescription)")
            }
        }
    }
    private func sendMessage() {
        guard appState.selectedModel != nil else {
            showingNoModelAlert = true
            return
        }
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasFiles = !attachedFiles.isEmpty
        guard hasText || hasFiles else { return }
        if appState.currentSession == nil {
            appState.newChat()
        }
        let messageContent = messageText.isEmpty ? "" : messageText
        var attachedFilesList: [AttachedFile] = []
        if !attachedFiles.isEmpty {
            for fileURL in attachedFiles {
                if fileURL.startAccessingSecurityScopedResource() {
                    defer { fileURL.stopAccessingSecurityScopedResource() }
                    do {
                        let fileExtension = fileURL.pathExtension.lowercased()
                        let fileName = fileURL.lastPathComponent
                        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                        let fileSize = fileAttributes[.size] as? Int64 ?? 0
                        let attachedFile = AttachedFile(
                            fileName: fileName,
                            filePath: fileURL.path,
                            fileType: fileExtension,
                            fileSize: fileSize
                        )
                        attachedFilesList.append(attachedFile)
                    } catch {
                    }
                }
            }
        }
        let userMessage = ChatMessage(
            content: messageContent.isEmpty && !attachedFilesList.isEmpty ? "(Attached files)" : messageContent,
            isFromUser: true,
            timestamp: Date(),
            attachedFiles: attachedFilesList.isEmpty ? nil : attachedFilesList
        )
        appState.addMessage(userMessage)
        let currentMessage = messageContent.isEmpty && !attachedFilesList.isEmpty ? "(Attached files)" : messageContent
        if !attachedFiles.isEmpty {
        }
        messageText = ""
        attachedFiles.removeAll()
        guard let sessionId = appState.currentSession?.id else { return }
        sessionTypingState[sessionId] = true
        sessionStreamingContent[sessionId] = ""
        sessionStreamingId[sessionId] = UUID()
        if appState.selectedModel == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let sessionId = self.appState.currentSession?.id {
                    self.sessionTypingState[sessionId] = false
                    self.sessionStreamingId[sessionId] = nil
                }
                let errorMessage = ChatMessage(
                    content: "**No AI Model Selected**\n\nI can't respond to your message because no AI model has been selected. Please go to the Models tab and select or download an AI model to start chatting.\n\n**How to fix this:**\n1. Click on the \"Models\" tab at the top\n2. Download a model from Hugging Face or select an existing one\n3. Come back here and try your message again",
                    isFromUser: false,
                    timestamp: Date()
                )
                self.appState.addMessage(errorMessage)
            }
        } else if !appState.selectedModel!.isDownloaded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let sessionId = self.appState.currentSession?.id {
                    self.sessionTypingState[sessionId] = false
                    self.sessionStreamingId[sessionId] = nil
                }
                let errorMessage = ChatMessage(
                    content: "**Model Still Downloading**\n\nThe selected model \"\(appState.selectedModel!.name)\" is still downloading. Please wait for the download to complete before chatting.\n\n**Current status:** Downloading...\n\nYou can check the progress in the Models tab. Once the download finishes, you'll be able to chat with this model.",
                    isFromUser: false,
                    timestamp: Date()
                )
                self.appState.addMessage(errorMessage)
            }
        } else {
            if !LlamaCPPManager.shared.isModelLoaded {
                LlamaCPPManager.shared.loadModel(appState.selectedModel!)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if LlamaCPPManager.shared.isModelLoaded {
                        self.generateAIResponse(for: currentMessage)
                    } else {
                        if let sessionId = self.appState.currentSession?.id {
                            self.sessionTypingState[sessionId] = false
                            self.sessionStreamingId[sessionId] = nil
                        }
                        let errorMessage = ChatMessage(
                            content: "**Model Loading Failed**\n\nI couldn't load the selected model \"\(self.appState.selectedModel!.name)\". This might be due to:\n\n• **Corrupted model file** - Try re-downloading the model\n• **Insufficient memory** - Close other applications and try again\n• **File permission issues** - Make sure the app has access to the Models folder\n\n**Troubleshooting steps:**\n1. Go to Models tab and delete the problematic model\n2. Re-download it from Hugging Face\n3. Try again",
                            isFromUser: false,
                            timestamp: Date()
                        )
                        self.appState.addMessage(errorMessage)
                    }
                }
            } else {
                generateAIResponse(for: currentMessage)
            }
        }
    }
    private func generateAIResponse(for prompt: String) {
        let sessionTitle = appState.currentSession?.title ?? "Unknown"
        let sessionId = appState.currentSession?.id.uuidString.prefix(8) ?? "none"
        guard let currentSessionId = appState.currentSession?.id else {
            return
        }
        let requestSessionId = currentSessionId
        LlamaCPPManager.shared.generateResponse(
            prompt: prompt,
            sessionId: currentSessionId, // Each session gets its own llama.cpp process
            conversationHistory: appState.chatMessages, // Only current session's messages
            onToken: nil, // No streaming - wait for complete response
            onComplete: { [weak appState] response in
                DispatchQueue.main.async {
                    self.sessionTypingState[requestSessionId] = false
                    self.sessionStreamingId[requestSessionId] = nil
                    self.sessionStreamingContent[requestSessionId] = ""
                    guard let appState = appState else {
                        return
                    }
                    if !response.isEmpty && response != "Generating stopped by user." {
                        let aiMessage = ChatMessage(
                            content: response,
                            isFromUser: false,
                            timestamp: Date()
                        )
                        if let sessionIndex = appState.chatSessions.firstIndex(where: { $0.id == requestSessionId }) {
                            appState.chatSessions[sessionIndex].messages.append(aiMessage)
                            appState.saveChatSessions()
                            if appState.currentSession?.id == requestSessionId {
                                appState.chatMessages.append(aiMessage)
                            }
                        }
                    } else {
                    }
                    if appState.currentSession?.id == requestSessionId {
                        self.isMessageFieldFocused = true
                    }
                }
            }
        )
    }
    private func stopGeneration() {
        guard let sessionId = appState.currentSession?.id else { return }
        LlamaCPPManager.shared.stopGeneration(for: sessionId)
        DispatchQueue.main.async {
            self.sessionTypingState[sessionId] = false
            let content = self.sessionStreamingContent[sessionId] ?? ""
            if !content.isEmpty {
                let aiMessage = ChatMessage(
                    content: content,
                    isFromUser: false,
                    timestamp: Date()
                )
                self.appState.addMessage(aiMessage)
            }
            
            let stoppedMessage = ChatMessage(
                content: "Generation stopped by user.",
                isFromUser: false,
                timestamp: Date()
            )
            self.appState.addMessage(stoppedMessage)
            
            self.sessionStreamingId[sessionId] = nil
            self.sessionStreamingContent[sessionId] = ""
        }
    }
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if isTyping, let streamingId = streamingMessageId {
            if animated {
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo(streamingId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(streamingId, anchor: .bottom)
            }
        } else if let lastMessage = appState.chatMessages.last {
            if animated {
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    private func removeFile(_ fileURL: URL) {
        if let index = attachedFiles.firstIndex(of: fileURL) {
            attachedFiles.remove(at: index)
        }
    }
}
struct FileCardView: View {
    let fileURL: URL
    let onRemove: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: fileURL.pathExtension == "pdf" ? "doc.fill" : "doc.text.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    Text(fileURL.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 60)
                }
                .frame(width: 70, height: 70)
                .background(Color(white: 0.08))
                .cornerRadius(8)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
            }
        }
    }
}
struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var isCopied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(isCopied ? "Copied!" : "Copy")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(isCopied ? .green : .white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightSyntax(code: code, language: language))
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color.black.opacity(0.4))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    private func highlightSyntax(code: String, language: String) -> AttributedString {
        var attributedString = AttributedString(code)
        let keywordColor = Color(red: 0.8, green: 0.4, blue: 0.9) // Purple
        let stringColor = Color(red: 0.6, green: 0.9, blue: 0.6)  // Green
        let commentColor = Color(red: 0.5, green: 0.5, blue: 0.5) // Gray
        let functionColor = Color(red: 0.3, green: 0.7, blue: 1.0) // Blue
        let numberColor = Color(red: 1.0, green: 0.7, blue: 0.4)  // Orange
        let defaultColor = Color.white
        let keywords: [String] = {
            let common = ["if", "else", "for", "while", "do", "switch", "case", "break", "continue", "return", "func", "function", "def", "class", "struct", "enum", "var", "let", "const", "import", "from", "as", "try", "catch", "throw", "async", "await", "public", "private", "protected", "static", "void", "int", "string", "bool", "true", "false", "nil", "null", "self", "this", "super", "new", "delete"]
            switch language.lowercased() {
            case "python":
                return common + ["lambda", "yield", "with", "pass", "raise", "finally", "except", "assert", "global", "nonlocal", "elif", "in", "is", "not", "and", "or", "None", "True", "False"]
            case "javascript", "js", "typescript", "ts":
                return common + ["typeof", "instanceof", "in", "of", "yield", "delete", "void", "undefined", "export", "default", "extends", "implements", "interface", "type"]
            case "swift":
                return common + ["guard", "defer", "inout", "extension", "protocol", "typealias", "associatedtype", "mutating", "override", "final", "required", "convenience", "dynamic", "lazy", "optional", "throws", "rethrows", "where"]
            default:
                return common
            }
        }()
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        var currentPosition = attributedString.startIndex
        for line in lines {
            let lineString = String(line)
            if lineString.trimmingCharacters(in: .whitespaces).hasPrefix("//") ||
               lineString.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                let lineEnd = attributedString.index(currentPosition, offsetByCharacters: lineString.count)
                if lineEnd <= attributedString.endIndex {
                    attributedString[currentPosition..<lineEnd].foregroundColor = commentColor
                }
            } else {
                highlightStrings(in: &attributedString, line: lineString, startPos: currentPosition, color: stringColor)
                highlightNumbers(in: &attributedString, line: lineString, startPos: currentPosition, color: numberColor)
                for keyword in keywords {
                    highlightKeyword(in: &attributedString, keyword: keyword, line: lineString, startPos: currentPosition, color: keywordColor)
                }
                highlightFunctions(in: &attributedString, line: lineString, startPos: currentPosition, color: functionColor)
            }
            let lineLength = lineString.count + 1
            let newPos = attributedString.index(currentPosition, offsetByCharacters: lineLength)
            if newPos <= attributedString.endIndex {
                currentPosition = newPos
            } else {
                break
            }
        }
        for run in attributedString.runs {
            if attributedString[run.range].foregroundColor == nil {
                attributedString[run.range].foregroundColor = defaultColor
            }
        }
        return attributedString
    }
    private func highlightStrings(in attributedString: inout AttributedString, line: String, startPos: AttributedString.Index, color: Color) {
        let patterns = ["\"[^\"]*\"", "'[^']*'", "`[^`]*`"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsLine = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
                for match in matches {
                    if let range = Range(match.range, in: line) {
                        let startOffset = line.distance(from: line.startIndex, to: range.lowerBound)
                        let endOffset = line.distance(from: line.startIndex, to: range.upperBound)
                        let attrStart = attributedString.index(startPos, offsetByCharacters: startOffset)
                        let attrEnd = attributedString.index(startPos, offsetByCharacters: endOffset)
                        if attrStart < attributedString.endIndex && attrEnd <= attributedString.endIndex {
                            attributedString[attrStart..<attrEnd].foregroundColor = color
                        }
                    }
                }
            }
        }
    }
    private func highlightNumbers(in attributedString: inout AttributedString, line: String, startPos: AttributedString.Index, color: Color) {
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                if let range = Range(match.range, in: line) {
                    let startOffset = line.distance(from: line.startIndex, to: range.lowerBound)
                    let endOffset = line.distance(from: line.startIndex, to: range.upperBound)
                    let attrStart = attributedString.index(startPos, offsetByCharacters: startOffset)
                    let attrEnd = attributedString.index(startPos, offsetByCharacters: endOffset)
                    if attrStart < attributedString.endIndex && attrEnd <= attributedString.endIndex {
                        attributedString[attrStart..<attrEnd].foregroundColor = color
                    }
                }
            }
        }
    }
    private func highlightKeyword(in attributedString: inout AttributedString, keyword: String, line: String, startPos: AttributedString.Index, color: Color) {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                if let range = Range(match.range, in: line) {
                    let startOffset = line.distance(from: line.startIndex, to: range.lowerBound)
                    let endOffset = line.distance(from: line.startIndex, to: range.upperBound)
                    let attrStart = attributedString.index(startPos, offsetByCharacters: startOffset)
                    let attrEnd = attributedString.index(startPos, offsetByCharacters: endOffset)
                    if attrStart < attributedString.endIndex && attrEnd <= attributedString.endIndex {
                        attributedString[attrStart..<attrEnd].foregroundColor = color
                    }
                }
            }
        }
    }
    private func highlightFunctions(in attributedString: inout AttributedString, line: String, startPos: AttributedString.Index, color: Color) {
        if let regex = try? NSRegularExpression(pattern: "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(") {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let funcRange = match.range(at: 1)
                    if let range = Range(funcRange, in: line) {
                        let startOffset = line.distance(from: line.startIndex, to: range.lowerBound)
                        let endOffset = line.distance(from: line.startIndex, to: range.upperBound)
                        let attrStart = attributedString.index(startPos, offsetByCharacters: startOffset)
                        let attrEnd = attributedString.index(startPos, offsetByCharacters: endOffset)
                        if attrStart < attributedString.endIndex && attrEnd <= attributedString.endIndex {
                            attributedString[attrStart..<attrEnd].foregroundColor = color
                        }
                    }
                }
            }
        }
    }
}
struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var parsedContent: AttributedString?
    private func extractCodeBlocks(_ content: String) -> [(language: String, code: String, range: Range<String.Index>)] {
        var blocks: [(String, String, Range<String.Index>)] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if let languageRange = Range(match.range(at: 1), in: content),
                   let codeRange = Range(match.range(at: 2), in: content),
                   let fullRange = Range(match.range, in: content) {
                    let language = String(content[languageRange]).isEmpty ? "code" : String(content[languageRange])
                    let code = String(content[codeRange])
                    blocks.append((language, code, fullRange))
                }
            }
        }
        return blocks
    }
    struct ContentPart {
        let content: String
        let isCode: Bool
        let language: String?
    }
    private func splitContentWithCodeBlocks(_ content: String, codeBlocks: [(language: String, code: String, range: Range<String.Index>)]) -> [ContentPart] {
        var parts: [ContentPart] = []
        var currentIndex = content.startIndex
        for block in codeBlocks {
            if currentIndex < block.range.lowerBound {
                let textContent = String(content[currentIndex..<block.range.lowerBound])
                parts.append(ContentPart(content: textContent, isCode: false, language: nil))
            }
            parts.append(ContentPart(content: block.code, isCode: true, language: block.language))
            currentIndex = block.range.upperBound
        }
        if currentIndex < content.endIndex {
            let textContent = String(content[currentIndex..<content.endIndex])
            parts.append(ContentPart(content: textContent, isCode: false, language: nil))
        }
        return parts
    }
    private func parseMarkdown(_ content: String) -> AttributedString {
        if let cached = parsedContent {
            return cached
        }
        do {
            var attributedString = try AttributedString(markdown: content, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            attributedString.foregroundColor = .white
            return attributedString
        } catch {
            return AttributedString(content)
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !message.isFromUser {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "brain")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    )
                VStack(alignment: .leading, spacing: 12) {
                    let codeBlocks = extractCodeBlocks(message.content)
                    if codeBlocks.isEmpty {
                        Text(parseMarkdown(message.content))
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .textSelection(.enabled)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.12))
                            .cornerRadius(16)
                            .onAppear {
                                if parsedContent == nil {
                                    parsedContent = parseMarkdown(message.content)
                                }
                            }
                    } else {
                        let parts = splitContentWithCodeBlocks(message.content, codeBlocks: codeBlocks)
                        ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                            if part.isCode {
                                CodeBlockView(code: part.content, language: part.language ?? "code")
                            } else if !part.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(parseMarkdown(part.content))
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(white: 0.12))
                                    .cornerRadius(16)
                            }
                        }
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                Spacer()
            } else {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .textSelection(.enabled)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(red: 7/255, green: 31/255, blue: 51/255))
                            .cornerRadius(16)
                            .frame(maxWidth: 600, alignment: .trailing)
                    }
                    if let files = message.attachedFiles, !files.isEmpty {
                        VStack(alignment: .trailing, spacing: 6) {
                            ForEach(files) { file in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.fileName)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text("\(file.fileType.uppercased()) • \(file.fileSizeFormatted)")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(red: 7/255, green: 31/255, blue: 51/255).opacity(0.7))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .frame(maxWidth: 600, alignment: .trailing)
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isFromUser ? .trailing : .leading)
    }
}
struct TypingIndicatorView: View {
    @State private var animationOffset: CGFloat = 0
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "brain")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                )
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .offset(y: animationOffset)
                        .animation(
                            Animation
                                .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationOffset
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.12))
            .cornerRadius(16)
            Spacer()
        }
        .onAppear {
            animationOffset = -4
        }
    }
}
