import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var notificationManager: NotificationManager
    @StateObject private var recorder = AudioRecorder()

    @State private var inputText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var importedFiles: [URL] = []
    @State private var showingSettings = false
    @State private var showingFileImporter = false
    @State private var generatedTask = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                taskList
                composer
            }
            .navigationTitle("每日任务")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(taskStore)
                    .environmentObject(notificationManager)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    importedFiles.append(contentsOf: urls)
                }
            }
            .alert("提示", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var taskList: some View {
        List {
            if taskStore.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("还没有任务")
                        .font(.headline)
                    Text("在下方输入文字、录音或图片，整理后发送即可开始每日提醒。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
                .listRowSeparator(.hidden)
            } else {
                ForEach(taskStore.tasks) { task in
                    TaskRow(task: task) {
                        taskStore.completeTask(id: task.id)
                    } onDelete: {
                        taskStore.deleteTask(id: task.id)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if !generatedTask.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("整理后的任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $generatedTask)
                        .frame(minHeight: 76, maxHeight: 118)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button {
                        Task { await saveGeneratedTask() }
                    } label: {
                        Label("发送并开始推送", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(generatedTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("输入文字、语音、图片或附件", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await toggleRecording() }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                }
                .accessibilityLabel(recorder.isRecording ? "停止录音" : "开始录音")

                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                }
                .accessibilityLabel("选择图片")

                Button {
                    showingFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title2)
                }
                .accessibilityLabel("上传附件")

                Button {
                    Task { await generateTaskPreview() }
                } label: {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .accessibilityLabel("发送")
                .disabled(isProcessing || !hasInput)
            }

            if hasAttachmentInput {
                HStack(spacing: 8) {
                    if let audioURL = recorder.currentRecordingURL {
                        Label(audioURL.lastPathComponent, systemImage: "waveform")
                            .lineLimit(1)
                    }
                    if !selectedPhotos.isEmpty {
                        Label("\(selectedPhotos.count) 张图片", systemImage: "photo")
                    }
                    if !importedFiles.isEmpty {
                        Label("\(importedFiles.count) 个附件", systemImage: "paperclip")
                    }
                    Spacer()
                    Button("清空") {
                        clearDraft()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
    }

    private var hasInput: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachmentInput
    }

    private var hasAttachmentInput: Bool {
        recorder.currentRecordingURL != nil || !selectedPhotos.isEmpty || !importedFiles.isEmpty
    }

    private func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            await recorder.startRecording()
        }
        if let message = recorder.errorMessage {
            errorMessage = message
            recorder.errorMessage = nil
        }
    }

    private func generateTaskPreview() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let apiKey = try KeychainService.readAPIKey()
            guard let apiKey, !apiKey.isEmpty else { throw GLMError.missingAPIKey }

            let savedImages = try await saveSelectedImages()
            let savedFiles = try copyImportedFiles()
            var rawParts = [inputText]

            var attachments = savedImages.attachments + savedFiles
            if let audioURL = recorder.currentRecordingURL {
                let chunks = try await recorder.splitForASRIfNeeded(url: audioURL)
                let client = GLMClient(apiKey: apiKey)
                var transcriptions: [String] = []
                for chunk in chunks {
                    transcriptions.append(try await client.transcribeAudio(fileURL: chunk))
                }
                let audioText = transcriptions.joined(separator: "\n")
                if !audioText.isEmpty {
                    rawParts.append("语音转写：\(audioText)")
                }
                attachments.append(AttachmentItem(kind: .audio, localPath: audioURL.path, displayName: audioURL.lastPathComponent))
            }

            if !savedFiles.isEmpty {
                rawParts.append("附件：\(savedFiles.map(\.displayName).joined(separator: "、"))")
            }

            let rawText = rawParts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            let client = GLMClient(apiKey: apiKey)
            generatedTask = try await client.summarizeTask(text: rawText, imageURLs: savedImages.urls)
            pendingAttachments = attachments
            pendingRawText = rawText
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @State private var pendingAttachments: [AttachmentItem] = []
    @State private var pendingRawText = ""

    private func saveGeneratedTask() async {
        let title = generatedTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = taskStore.addTask(title: title, rawText: pendingRawText, attachments: pendingAttachments)
        await notificationManager.schedule(task: task)
        clearDraft()
    }

    private func clearDraft() {
        inputText = ""
        selectedPhotos = []
        importedFiles = []
        generatedTask = ""
        pendingAttachments = []
        pendingRawText = ""
        recorder.stopRecording()
    }

    private func saveSelectedImages() async throws -> (urls: [URL], attachments: [AttachmentItem]) {
        var urls: [URL] = []
        var attachments: [AttachmentItem] = []

        for item in selectedPhotos {
            guard let data = try await item.loadTransferable(type: Data.self) else { continue }
            let url = Self.attachmentDirectory().appendingPathComponent("image-\(UUID().uuidString).jpg")
            try data.write(to: url, options: .atomic)
            urls.append(url)
            attachments.append(AttachmentItem(kind: .image, localPath: url.path, displayName: url.lastPathComponent))
        }
        return (urls, attachments)
    }

    private func copyImportedFiles() throws -> [AttachmentItem] {
        try importedFiles.map { source in
            let didStart = source.startAccessingSecurityScopedResource()
            defer {
                if didStart { source.stopAccessingSecurityScopedResource() }
            }
            let destination = Self.attachmentDirectory().appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return AttachmentItem(kind: .file, localPath: destination.path, displayName: destination.lastPathComponent)
        }
    }

    private static func attachmentDirectory() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let onComplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                Spacer()
                if task.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 12) {
                Label(task.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label(String(format: "%02d:%02d", task.reminderHour, task.reminderMinute), systemImage: "bell")
                if !task.attachments.isEmpty {
                    Label("\(task.attachments.count)", systemImage: "paperclip")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                if !task.isCompleted {
                    Button("完成", action: onComplete)
                        .buttonStyle(.bordered)
                }
                Button("删除", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}

