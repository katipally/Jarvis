import SwiftUI
import UniformTypeIdentifiers

// MARK: - File Upload View (HIG Compliant)
// Following Apple Human Interface Guidelines for drag and drop

struct FileUploadView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var isTargeted = false
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Drop Zone (HIG: Clear drop target)
            dropZone
            
            // Attached Files List
            if !viewModel.attachedFiles.isEmpty {
                attachedFilesList
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
    }
    
    // MARK: - Drop Zone
    private var dropZone: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isTargeted ? AnyShapeStyle(.blue.opacity(0.1)) : AnyShapeStyle(.quaternary))
                    .frame(width: 64, height: 64)
                
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isTargeted ? .blue : .secondary)
            }
            .animation(.spring(response: 0.3), value: isTargeted)
            
            // Text
            VStack(spacing: 4) {
                Text(isTargeted ? "Drop files here" : "Drag files here")
                    .font(.headline)
                
                Text("or click to browse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Supported formats
            HStack(spacing: 8) {
                ForEach(["PDF", "Images", "Text"], id: \.self) { type in
                    Text(type)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargeted ? AnyShapeStyle(.blue) : AnyShapeStyle(.quaternary),
                            style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [8, 4])
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { showFilePicker = true }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.spring(response: 0.3), value: isTargeted)
    }
    
    // MARK: - Attached Files List
    private var attachedFilesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attached Files")
                .font(.headline)
            
            ForEach(viewModel.attachedFiles, id: \.self) { file in
                FileRow(
                    fileName: file.lastPathComponent,
                    fileExtension: file.pathExtension,
                    onRemove: { viewModel.removeFile(file) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Supported Types
    private var supportedTypes: [UTType] {
        [.pdf, .plainText, .image, .png, .jpeg, .heic, .json, .xml]
    }
    
    // MARK: - Handlers
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                DispatchQueue.main.async {
                    viewModel.attachFiles([url])
                }
            }
        }
        return true
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            viewModel.attachFiles(urls)
        }
    }
}

// MARK: - File Row
struct FileRow: View {
    let fileName: String
    let fileExtension: String
    let onRemove: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // File Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
            }
            
            // File Info
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.body)
                    .lineLimit(1)
                
                Text(fileExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Remove Button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(12)
        .background(isHovered ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
    }
    
    private var iconName: String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "heic", "gif": return "photo.fill"
        case "txt", "md": return "doc.text.fill"
        case "swift", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        case "json", "xml": return "curlybraces"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        switch fileExtension.lowercased() {
        case "pdf": return .red
        case "png", "jpg", "jpeg", "heic", "gif": return .green
        case "txt", "md": return .blue
        case "swift": return .orange
        case "py": return .yellow
        case "js", "ts": return .yellow
        default: return .gray
        }
    }
}

#Preview {
    FileUploadView(viewModel: ChatViewModel())
        .frame(width: 400)
        .padding()
}
