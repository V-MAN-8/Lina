import SwiftUI
struct ModelsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingModelPicker = false
    @State private var isAddButtonHovered = false
    @State private var isFABHovered = false
    var body: some View {
        VStack(spacing: 0) {
            if appState.downloadedModels.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 110)
                    VStack(spacing: 20) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.2))
                        VStack(spacing: 10) {
                            Text("No models yet")
                                .font(.title2.bold())
                                .foregroundColor(.white.opacity(0.8))
                            Text("Download AI models from Hugging Face to get started")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.downloadedModels) { model in
                            ModelRowView(
                                model: model,
                                isSelected: appState.selectedModel?.id == model.id
                            ) {
                                if model.isDownloaded {
                                    appState.selectModel(model)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .background(Color.black)
            }
        }
        .background(Color.black)
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView()
        }
    }
}
struct ModelRowView: View {
    let model: AIModel
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var showingDetails = false
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Circle()
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color(white: 0.12))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "cube.fill")
                            .font(.title3)
                            .foregroundColor(isSelected ? .blue : .white.opacity(0.6))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(model.isDownloaded ? FileManagerUtility.shared.formatFileSize(FileManagerUtility.shared.getModelFileSize(model)) : model.size)
                            .font(.system(size: 13))
                            .foregroundColor(!model.isDownloaded ? .blue : .white.opacity(0.5))
                        if isSelected {
                            Text("• Active")
                                .font(.system(size: 13))
                                .foregroundColor(.blue)
                        }
                    }
                }
                Spacer()
                Menu {
                    Button("Model Details") {
                        showingDetails = true
                    }
                    Divider()
                    Button("Delete Model", role: .destructive) {
                        deleteModel()
                    }
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "ellipsis")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 14, weight: .medium))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                if model.isDownloaded {
                    onSelect()
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }
            if !model.isDownloaded {
                VStack(spacing: 8) {
                    ProgressView(value: model.downloadProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    HStack {
                        if model.totalBytes > 0 {
                            let downloadedSize = FileManagerUtility.shared.formatFileSize(model.downloadedBytes)
                            let totalSize = FileManagerUtility.shared.formatFileSize(model.totalBytes)
                            Text("\(downloadedSize) / \(totalSize) downloaded")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        } else if model.downloadedBytes > 0 {
                            let downloadedSize = FileManagerUtility.shared.formatFileSize(model.downloadedBytes)
                            Text("\(downloadedSize) downloaded")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        } else {
                            Text("Starting download...")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        if model.downloadSpeed > 0 {
                            Text(String(format: "%.1f MB/s", model.downloadSpeed))
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(isSelected ? Color.blue.opacity(0.1) : (isHovered && model.isDownloaded ? Color.blue.opacity(0.05) : Color(white: 0.08)))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.3) : (isHovered && model.isDownloaded ? Color.blue.opacity(0.2) : Color.clear), lineWidth: 1)
        )
        .scaleEffect(isHovered && model.isDownloaded ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .sheet(isPresented: $showingDetails) {
            ModelDetailsView(model: model)
        }
    }
    private func deleteModel() {
        appState.deleteModel(model)
    }
}
struct ModelDetailsView: View {
    let model: AIModel
    @Environment(\.dismiss) var dismiss
    @State private var isDoneButtonHovered = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Model Details")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        .cornerRadius(8)
                        .scaleEffect(isDoneButtonHovered ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isDoneButtonHovered)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isDoneButtonHovered = hovering
                }
            }
            .padding()
            .background(Color.black)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailRow(label: "Name", value: model.name)
                    DetailRow(label: "Source URL", value: model.url)
                    DetailRow(label: "File Size", value: model.isDownloaded ? FileManagerUtility.shared.formatFileSize(FileManagerUtility.shared.getModelFileSize(model)) : model.size)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        HStack(spacing: 8) {
                            Circle()
                                .fill(model.isDownloaded ? Color.blue : Color.blue.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text(model.isDownloaded ? "Downloaded and ready" : "Downloading...")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                    }
                    if model.isDownloaded && !model.filePath.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            Text("Parameters and chat template are automatically extracted from the GGUF model file.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.black)
        }
        .frame(width: 500, height: 400)
        .background(Color.black)
    }
}
struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#Preview {
    ModelsView()
        .environmentObject(AppState())
}
