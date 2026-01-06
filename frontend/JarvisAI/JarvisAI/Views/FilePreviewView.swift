import SwiftUI

struct FilePreviewRow: View {
    let fileNames: [String]
    let fileIds: [String]
    let isUser: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(fileNames.enumerated()), id: \.offset) { index, fileName in
                    FilePreviewChip(
                        fileName: fileName,
                        fileId: index < fileIds.count ? fileIds[index] : nil,
                        isUser: isUser
                    )
                }
            }
        }
    }
}

struct FilePreviewChip: View {
    let fileName: String
    let fileId: String?
    let isUser: Bool
    @State private var showPreview = false
    
    private var isImage: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext)
    }
    
    private var fileIcon: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo.fill"
        case "txt", "md": return "doc.text.fill"
        case "swift", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }
    
    var body: some View {
        Button(action: { showPreview = true }) {
            HStack(spacing: 6) {
                Image(systemName: fileIcon)
                    .font(.system(size: 10))
                Text(fileName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isUser ? .white.opacity(0.2) : .blue.opacity(0.1))
            )
            .foregroundStyle(isUser ? .white : .blue)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPreview) {
            FilePreviewPopover(fileName: fileName, fileId: fileId)
        }
    }
}

struct FilePreviewPopover: View {
    let fileName: String
    let fileId: String?
    
    private var isImage: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: isImage ? "photo.fill" : "doc.fill")
                    .foregroundStyle(.blue)
                Text(fileName)
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            if isImage, let fileId = fileId {
                AsyncImage(url: URL(string: "\(Config.apiBaseURL)/files/\(fileId)/preview")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(minWidth: 300, maxWidth: 600, minHeight: 200, maxHeight: 450)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Image preview not available")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 300, minHeight: 200)
                    case .empty:
                        ProgressView()
                            .frame(minWidth: 300, minHeight: 200)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Preview not available for this file type")
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 300, minHeight: 150)
            }
        }
        .padding(20)
        .frame(minWidth: 350, maxWidth: 650)
        .background(MacOS26Materials.sidebar)
    }
}
