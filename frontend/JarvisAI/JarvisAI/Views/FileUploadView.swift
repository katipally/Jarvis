import SwiftUI
import UniformTypeIdentifiers

/// File Upload View for drag-and-drop and file selection
struct FileUploadView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var isDropTargeted = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            // Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? Color.blue : Color.gray.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDropTargeted ? Color.blue.opacity(0.1) : Color.clear)
                    )
                
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 36))
                        .foregroundStyle(isDropTargeted ? .blue : .secondary)
                    
                    Text("Drop files here")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("or")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    
                    Button(action: { viewModel.showFilePicker = true }) {
                        Label("Browse Files", systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                .padding(24)
            }
            .frame(height: 180)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
            
            // Supported Formats
            HStack(spacing: 16) {
                ForEach(supportedFormats, id: \.0) { format, icon in
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                        Text(format)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            
            // Attached Files List
            if !viewModel.attachedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attached Files")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    ForEach(viewModel.attachedFiles, id: \.self) { file in
                        AttachedFileRow(file: file) {
                            viewModel.removeFile(file)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.pdf, .plainText, .image, .png, .jpeg],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.attachFiles(urls)
            }
        }
    }
    
    private var supportedFormats: [(String, String)] {
        [
            ("PDF", "doc.fill"),
            ("Images", "photo.fill"),
            ("Text", "doc.text.fill"),
            ("Code", "curlybraces")
        ]
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    if let data = data as? Data,
                       let urlString = String(data: data, encoding: .utf8),
                       let url = URL(string: urlString) {
                        DispatchQueue.main.async {
                            viewModel.attachFiles([url])
                        }
                    }
                }
            }
        }
        return true
    }
}

struct AttachedFileRow: View {
    let file: URL
    let onRemove: () -> Void
    
    private var fileIcon: String {
        let ext = file.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo.fill"
        case "txt", "md": return "doc.text.fill"
        case "swift", "py", "js", "ts", "json": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text(file.pathExtension.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

struct FileUploadPreviewContainer: View {
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        FileUploadView(viewModel: viewModel)
            .padding()
            .frame(width: 400)
    }
}

#Preview {
    FileUploadPreviewContainer()
}

