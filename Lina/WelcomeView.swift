import SwiftUI
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingModelPicker = false
    @State private var isButtonHovered = false
    private let logoSize: CGFloat = 100                    // Logo width and height
    private let logoToNameSpacing: CGFloat = 20            // Space between logo and app name
    private let appNameFontSize: CGFloat = 48              // App name font size
    private let nameToDescriptionSpacing: CGFloat = 18      // Space between name and description
    private let descriptionToButtonSpacing: CGFloat = 40   // Space between description and button
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoSize, height: logoSize)
                    Spacer()
                        .frame(height: logoToNameSpacing)
                    Text("Lina")
                        .font(.system(size: appNameFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                        .frame(height: nameToDescriptionSpacing)
                    Text("Your Personal AI Model Runner")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                        .frame(height: descriptionToButtonSpacing)
                    Button(action: {
                        showingModelPicker = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 17))
                            Text("Add Model")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        .cornerRadius(10)
                        .contentShape(Rectangle())
                        .scaleEffect(isButtonHovered ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isButtonHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isButtonHovered = hovering
                    }
                }
                .frame(maxWidth: .infinity)  // Center horizontally
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView()
                .frame(width: 600, height: 500)
        }
    }
}
struct CuratedModel: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let size: String
    let parameters: String
    let url: String
    let quantization: String
    let useCase: String
    static let recommendedModels: [CuratedModel] = [
        CuratedModel(
            name: "Gemma 2 2B Instruct",
            description: "Ultra-fast Google model, perfect for laptops and quick tasks",
            size: "1.6 GB",
            parameters: "2B",
            url: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Quick responses, low resources"
        ),
        CuratedModel(
            name: "Qwen2.5 3B Instruct",
            description: "Fast and efficient small model, great for general tasks",
            size: "1.9 GB",
            parameters: "3B",
            url: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf",
            quantization: "Q4_K_M",
            useCase: "General chat, quick responses"
        ),
        CuratedModel(
            name: "Phi-3 Mini 3.8B",
            description: "Microsoft's efficient small model with strong reasoning",
            size: "2.2 GB",
            parameters: "3.8B",
            url: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf",
            quantization: "Q4",
            useCase: "Reasoning, coding, chat"
        ),
        CuratedModel(
            name: "Llama 3.2 3B Instruct",
            description: "Meta's latest compact model with good performance",
            size: "2.0 GB",
            parameters: "3B",
            url: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "General purpose, fast"
        ),
        CuratedModel(
            name: "Phi-3.5 Mini 3.8B",
            description: "Microsoft's newest small model with strong reasoning",
            size: "2.3 GB",
            parameters: "3.8B",
            url: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Reasoning, efficient performance"
        ),
        CuratedModel(
            name: "Qwen2.5 7B Instruct",
            description: "Perfect balance of speed and capability, most popular size",
            size: "4.4 GB",
            parameters: "7B",
            url: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "General purpose, versatile"
        ),
        CuratedModel(
            name: "Mistral 7B Instruct v0.3",
            description: "Popular and powerful 7B model from Mistral AI",
            size: "4.4 GB",
            parameters: "7B",
            url: "https://huggingface.co/MaziyarPanahi/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3.Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Chat, reasoning, coding"
        ),
        CuratedModel(
            name: "Qwen2.5 Coder 7B",
            description: "Efficient coding model, lightweight alternative",
            size: "4.7 GB",
            parameters: "7B",
            url: "https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf",
            quantization: "Q4_K_M",
            useCase: "Coding, lightweight"
        ),
        CuratedModel(
            name: "Llama 3.1 8B Instruct",
            description: "Meta's excellent 8B model with great capability",
            size: "4.9 GB",
            parameters: "8B",
            url: "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "General purpose, versatile"
        ),
        CuratedModel(
            name: "Gemma 2 9B Instruct",
            description: "Google's powerful model with excellent reasoning and math",
            size: "5.4 GB",
            parameters: "9B",
            url: "https://huggingface.co/bartowski/gemma-2-9b-it-GGUF/resolve/main/gemma-2-9b-it-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Reasoning, math, science"
        ),
        CuratedModel(
            name: "CodeLlama 13B Instruct",
            description: "Meta's specialized coding model for programming tasks",
            size: "7.9 GB",
            parameters: "13B",
            url: "https://huggingface.co/TheBloke/CodeLlama-13B-Instruct-GGUF/resolve/main/codellama-13b-instruct.Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Code generation, debugging"
        ),
        CuratedModel(
            name: "Qwen2.5 14B Instruct",
            description: "Excellent balance of speed and capability",
            size: "8.5 GB",
            parameters: "14B",
            url: "https://huggingface.co/Qwen/Qwen2.5-14B-Instruct-GGUF/resolve/main/qwen2.5-14b-instruct-q4_k_m.gguf",
            quantization: "Q4_K_M",
            useCase: "Advanced chat, analysis, coding"
        ),
        CuratedModel(
            name: "Gemma 2 27B Instruct",
            description: "Google's large model with strong performance across tasks",
            size: "16 GB",
            parameters: "27B",
            url: "https://huggingface.co/bartowski/gemma-2-27b-it-GGUF/resolve/main/gemma-2-27b-it-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Advanced tasks, high quality"
        ),
        CuratedModel(
            name: "Qwen2.5 32B Instruct",
            description: "High-quality responses with strong reasoning",
            size: "19 GB",
            parameters: "32B",
            url: "https://huggingface.co/Qwen/Qwen2.5-32B-Instruct-GGUF/resolve/main/qwen2.5-32b-instruct-q4_k_m.gguf",
            quantization: "Q4_K_M",
            useCase: "Professional tasks, complex reasoning"
        ),
        CuratedModel(
            name: "Qwen2.5 Coder 32B",
            description: "Specialized coding model with exceptional performance",
            size: "19 GB",
            parameters: "32B",
            url: "https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct-GGUF/resolve/main/qwen2.5-coder-32b-instruct-q4_k_m.gguf",
            quantization: "Q4_K_M",
            useCase: "Advanced coding, debugging, refactoring"
        ),
        CuratedModel(
            name: "DeepSeek Coder 33B",
            description: "Top-tier coding assistant with deep understanding",
            size: "19 GB",
            parameters: "33B",
            url: "https://huggingface.co/TheBloke/deepseek-coder-33b-instruct-GGUF/resolve/main/deepseek-coder-33b-instruct.Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Professional coding, architecture design"
        ),
        CuratedModel(
            name: "Mixtral 8x7B Instruct",
            description: "Mistral's MoE model - 47B total, uses ~13B actively",
            size: "26 GB",
            parameters: "47B (8x7B MoE)",
            url: "https://huggingface.co/TheBloke/Mixtral-8x7B-Instruct-v0.1-GGUF/resolve/main/mixtral-8x7b-instruct-v0.1.Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Efficient large model, multilingual"
        ),
        CuratedModel(
            name: "Nous Hermes 2 Mixtral 8x7B",
            description: "Fine-tuned Mixtral with improved instruction following",
            size: "26 GB",
            parameters: "47B (8x7B MoE)",
            url: "https://huggingface.co/TheBloke/Nous-Hermes-2-Mixtral-8x7B-DPO-GGUF/resolve/main/nous-hermes-2-mixtral-8x7b-dpo.Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Enhanced chat, instruction following"
        ),
        CuratedModel(
            name: "Llama 3.3 70B Instruct",
            description: "Meta's latest flagship - GPT-4 class performance",
            size: "40 GB",
            parameters: "70B",
            url: "https://huggingface.co/bartowski/Llama-3.3-70B-Instruct-GGUF/resolve/main/Llama-3.3-70B-Instruct-Q4_K_M.gguf",
            quantization: "Q4_K_M",
            useCase: "Professional use, complex reasoning"
        )
    ]
}
struct ModelCard: View {
    let model: CuratedModel
    let onDownload: () -> Void
    @State private var isHovered = false
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "brain")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(model.parameters)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                    Spacer()
                    Text(model.size)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                Text(model.description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(model.quantization, systemImage: "circle.grid.3x3.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Text("•")
                        .foregroundColor(.white.opacity(0.3))
                    Text(model.useCase)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .onHover { hovering in
            isHovered = hovering
        }
        .background(isHovered ? Color.blue.opacity(0.05) : Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.blue.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}
struct ModelPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var huggingFaceURL = ""
    @State private var modelName = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var selectedTab = 0 // 0 = Library, 1 = Download, 2 = Existing
    @State private var showingFilePicker = false
    @State private var isCancelButtonHovered = false
    @State private var isDownloadButtonHovered = false
    @State private var isBrowseButtonHovered = false
    @State private var selectedLibraryModel: CuratedModel? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(isCancelButtonHovered ? .blue : .white.opacity(0.6))
                .scaleEffect(isCancelButtonHovered ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isCancelButtonHovered)
                .onHover { hovering in
                    isCancelButtonHovered = hovering
                }
            }
            .padding()
            .background(Color.black.opacity(0.8))
            Text("Add AI Model")
                .font(.title.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 0)
                .padding(.bottom, 16)
                .background(Color.black)
            HStack(spacing: 0) {
                Button(action: { selectedTab = 0 }) {
                    VStack(spacing: 8) {
                        Text("Model Library")
                            .font(.system(size: 14, weight: selectedTab == 0 ? .semibold : .regular))
                            .foregroundColor(selectedTab == 0 ? .blue : .white.opacity(0.6))
                        Rectangle()
                            .fill(selectedTab == 0 ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                Button(action: { selectedTab = 1 }) {
                    VStack(spacing: 8) {
                        Text("Custom URL")
                            .font(.system(size: 14, weight: selectedTab == 1 ? .semibold : .regular))
                            .foregroundColor(selectedTab == 1 ? .blue : .white.opacity(0.6))
                        Rectangle()
                            .fill(selectedTab == 1 ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                Button(action: { selectedTab = 2 }) {
                    VStack(spacing: 8) {
                        Text("Local File")
                            .font(.system(size: 14, weight: selectedTab == 2 ? .semibold : .regular))
                            .foregroundColor(selectedTab == 2 ? .blue : .white.opacity(0.6))
                        Rectangle()
                            .fill(selectedTab == 2 ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
            .background(Color.black)
            ZStack {
                Color.black.ignoresSafeArea()
                if selectedTab == 0 {
                    libraryTabContent
                } else if selectedTab == 1 {
                    downloadTabContent
                } else {
                    existingModelTabContent
                }
            }
        }
        .frame(width: 600, height: 500)
        .alert("Download Status", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    private var libraryTabContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer()
                    .frame(height: 20)
                ForEach(CuratedModel.recommendedModels) { model in
                    ModelCard(model: model) {
                        downloadLibraryModel(model)
                    }
                }
                Spacer()
                    .frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
    }
    private var downloadTabContent: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Name (Optional)")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    TextField("Auto-detect from URL if empty", text: $modelName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .accentColor(.gray)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .padding(.horizontal, 40)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hugging Face Model URL")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    TextField("https://huggingface.co/username/model/resolve/main/file.gguf", text: $huggingFaceURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .accentColor(.gray)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .padding(.horizontal, 40)
                Text("Enter direct link to GGUF file (e.g., resolve/main/filename.gguf)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 40)
            }
            Button(action: downloadModel) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                    Text("Download Model")
                        .font(.headline)
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 2)
                )
                .cornerRadius(8)
                .scaleEffect(isDownloadButtonHovered ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDownloadButtonHovered)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .onHover { hovering in
                isDownloadButtonHovered = hovering
            }
            Spacer()
        }
    }
    private var existingModelTabContent: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))
                VStack(spacing: 8) {
                    Text("Select a GGUF Model File")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Choose a .gguf model file you already have on your computer")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                Button(action: {
                    showingFilePicker = true
                }) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                        Text("Browse Files")
                            .font(.headline)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                    .cornerRadius(8)
                    .scaleEffect(isBrowseButtonHovered ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isBrowseButtonHovered)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.top, 12)
                .onHover { hovering in
                    isBrowseButtonHovered = hovering
                }
            }
            Spacer()
        }
    }
    private func downloadLibraryModel(_ model: CuratedModel) {
        let newModel = AIModel(
            id: UUID(),
            name: model.name,
            url: model.url,
            isDownloaded: false,
            filePath: "",
            size: "Downloading...",
            downloadProgress: 0.0,
            downloadedBytes: 0,
            totalBytes: 0
        )
        appState.addModel(newModel)
        ModelDownloadManager.shared.downloadModel(newModel,
            progressHandler: { progress, downloadedBytes, totalBytes, downloadSpeed in
                DispatchQueue.main.async {
                    self.appState.updateModelProgress(newModel.id, 
                                                     progress: progress, 
                                                     downloadedBytes: downloadedBytes, 
                                                     totalBytes: totalBytes, 
                                                     downloadSpeed: downloadSpeed)
                }
            },
            completionHandler: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let filePath):
                        self.appState.completeModelDownload(newModel.id, filePath: filePath)
                    case .failure(let error):
                        print("[Download] Failed to download model: \(error)")
                        if let failedModel = self.appState.downloadedModels.first(where: { $0.id == newModel.id }) {
                            self.appState.deleteModel(failedModel)
                        }
                    }
                }
            }
        )
        DispatchQueue.main.async {
            appState.currentView = .models
            dismiss()
        }
    }
    private func downloadModel() {
        guard !huggingFaceURL.isEmpty else { return }
        let detectedModelName: String
        if modelName.isEmpty {
            if let url = URL(string: huggingFaceURL),
               let fileName = url.pathComponents.last {
                detectedModelName = fileName.replacingOccurrences(of: ".gguf", with: "")
            } else {
                detectedModelName = "Unknown Model"
            }
        } else {
            detectedModelName = modelName
        }
        guard URL(string: huggingFaceURL) != nil else {
            alertMessage = "Invalid URL format"
            showingAlert = true
            return
        }
        if !huggingFaceURL.contains("/resolve/") {
            alertMessage = "Please provide a direct download URL. It should contain '/resolve/main/' or '/resolve/master/' followed by the file name.\n\nExample:\nhttps://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf"
            showingAlert = true
            return
        }
        let newModel = AIModel(
            id: UUID(),
            name: detectedModelName,
            url: huggingFaceURL,
            isDownloaded: false,
            filePath: "",
            size: "Downloading...",
            downloadProgress: 0.0,
            downloadedBytes: 0,
            totalBytes: 0
        )
        appState.addModel(newModel)
        self.modelName = ""
        self.huggingFaceURL = ""
        DispatchQueue.main.async {
            appState.currentView = .models
            dismiss()
        }
        ModelDownloadManager.shared.downloadModel(newModel,
            progressHandler: { progress, downloadedBytes, totalBytes, downloadSpeed in
                DispatchQueue.main.async {
                    self.appState.updateModelProgress(newModel.id, progress: progress, downloadedBytes: downloadedBytes, totalBytes: totalBytes, downloadSpeed: downloadSpeed)
                }
            },
            completionHandler: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let filePath):
                        self.appState.completeModelDownload(newModel.id, filePath: filePath)
                    case .failure(let error):
                        print("Download failed: \(error)")
                        if let failedModel = self.appState.downloadedModels.first(where: { $0.id == newModel.id }) {
                            self.appState.deleteModel(failedModel)
                        }
                    }
                }
            }
        )
    }
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        do {
            let selectedFiles = try result.get()
            guard let selectedFile = selectedFiles.first else { return }
            guard selectedFile.pathExtension.lowercased() == "gguf" else {
                alertMessage = "Please select a .gguf model file"
                showingAlert = true
                return
            }
            _ = selectedFile.startAccessingSecurityScopedResource()
            defer {
                selectedFile.stopAccessingSecurityScopedResource()
            }
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: selectedFile.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0
            let fileSizeFormatted = FileManagerUtility.shared.formatFileSize(fileSize)
            let fileName = selectedFile.deletingPathExtension().lastPathComponent
            let modelsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Lina")
                .appendingPathComponent("Models")
            try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            let destinationURL = modelsDirectory.appendingPathComponent(selectedFile.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                alertMessage = "A model with this filename already exists"
                showingAlert = true
                return
            }
            try FileManager.default.copyItem(at: selectedFile, to: destinationURL)
            let newModel = AIModel(
                id: UUID(),
                name: fileName,
                url: "Local File",
                isDownloaded: true,
                filePath: destinationURL.path,
                size: fileSizeFormatted,
                downloadProgress: 1.0,
                downloadedBytes: fileSize,
                totalBytes: fileSize,
                downloadSpeed: 0.0
            )
            appState.addModel(newModel)
            DispatchQueue.main.async {
                dismiss()
            }
        } catch {
            alertMessage = "Error loading model: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}
#Preview {
    WelcomeView()
        .environmentObject(AppState())
}
