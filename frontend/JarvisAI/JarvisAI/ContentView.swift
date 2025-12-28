import SwiftUI
import MarkdownUI
import AppKit

// MARK: - App Theme
enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSettings = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarContent(viewModel: viewModel, showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            ChatDetailView(viewModel: viewModel, isInputFocused: $isInputFocused)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .preferredColorScheme(appTheme == .system ? nil : (appTheme == .dark ? .dark : .light))
        // MARK: - Keyboard Shortcuts
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewChat"))) { _ in
            DispatchQueue.main.async {
                viewModel.startNewChat()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleSidebar"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSettings"))) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusInput"))) { _ in
            isInputFocused = true
        }
        // Error alert
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("Dismiss") { viewModel.dismissError() }
            if let _ = viewModel.error {
                Button("Retry") {
                    viewModel.dismissError()
                    if let lastError = viewModel.messages.last, lastError.isError {
                        Task { await viewModel.retryFailedMessage(lastError) }
                    }
                }
            }
        } message: {
            Text(viewModel.error ?? "An unknown error occurred")
        }
    }
}

// MARK: - Sidebar Content
struct SidebarContent: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showSettings: Bool
    @State private var sortOrder: SortOrder = .newest
    @State private var editingId: String?
    @State private var editText: String = ""
    
    enum SortOrder: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case alphabetical = "A-Z"
    }
    
    var sortedConversations: [Conversation] {
        let filtered = viewModel.filteredConversations
        switch sortOrder {
        // Sort by creation time (when the conversation was started), not by last access
        case .newest: return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return filtered.sorted { $0.createdAt < $1.createdAt }
        case .alphabetical: return filtered.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // New Chat Button
            Button(action: {
                DispatchQueue.main.async {
                    viewModel.startNewChat()
                }
            }) {
                Label("New Chat", systemImage: "plus.message")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .keyboardShortcut("n", modifiers: .command)
            
            // Search - Full Text Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search conversations...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            
            // Search results indicator
            if !viewModel.searchText.isEmpty {
                HStack {
                    Text("\(sortedConversations.count) result\(sortedConversations.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            
            Divider()
            
            // Conversations List
            List(selection: Binding(
                get: { viewModel.currentConversationId },
                set: { id in
                    // Defer to avoid publishing changes during view updates
                    DispatchQueue.main.async {
                        if let id = id, let conv = viewModel.conversations.first(where: { $0.id == id }) {
                            viewModel.loadConversation(conv)
                        }
                    }
                }
            )) {
                Section {
                    ForEach(sortedConversations) { conversation in
                        ConversationListItem(
                            conversation: conversation,
                            isEditing: editingId == conversation.id,
                            editText: $editText,
                            onSave: {
                                viewModel.renameConversation(conversation, to: editText)
                                editingId = nil
                            },
                            onCancel: { editingId = nil }
                        )
                        .tag(conversation.id)
                        .contextMenu {
                            Button("Rename") {
                                editText = conversation.title
                                editingId = conversation.id
                            }
                            Button("Branch from here") {
                                DispatchQueue.main.async {
                                    if let lastMsg = conversation.messages.last {
                                        viewModel.loadConversation(conversation)
                                        viewModel.branchFromMessage(lastMsg)
                                    }
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                DispatchQueue.main.async {
                                    viewModel.deleteConversation(conversation)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                DispatchQueue.main.async {
                                    viewModel.deleteConversation(conversation)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Conversations")
                        Spacer()
                        Menu {
                            Picker("Sort By", selection: $sortOrder) {
                                ForEach(SortOrder.allCases, id: \.self) { order in
                                    Text(order.rawValue).tag(order)
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Footer with stats
            HStack {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(",", modifiers: .command)
                
                Spacer()
                
                Text("\(viewModel.conversations.count) chats")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .navigationTitle("Jarvis")
    }
}

// MARK: - Conversation List Item
struct ConversationListItem: View {
    let conversation: Conversation
    let isEditing: Bool
    @Binding var editText: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        if isEditing {
            HStack {
                TextField("Name", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(onSave)
                    .onAppear { isFocused = true }
                
                Button(action: onSave) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tint)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(conversation.updatedAt, style: .relative)
                        if conversation.totalTokens > 0 {
                            Text("•")
                            Text("\(conversation.totalTokens) tokens")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Chat Detail View
struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                chatBackground
                
                VStack(spacing: 0) {
                    if viewModel.messages.isEmpty {
                        EmptyStateView(viewModel: viewModel, isInputFocused: $isInputFocused)
                    } else {
                        MessagesListView(
                            viewModel: viewModel,
                            isInputFocused: $isInputFocused,
                            containerWidth: geometry.size.width
                        )
                    }
                }
                
                // Floating Input Bar
                VStack {
                    Spacer()
                    FloatingInputBar(viewModel: viewModel, isInputFocused: $isInputFocused)
                        .padding(.horizontal, calculateHorizontalPadding(for: geometry.size.width))
                        .padding(.bottom, 16)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Token counter
                if viewModel.currentTokenCount > 0 || viewModel.isLoading {
                    HStack(spacing: 4) {
                        Image(systemName: "number.circle")
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.currentTokenCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .help("Tokens used in current response")
                }
                
                StatusIndicator(isLoading: viewModel.isLoading)
                
                Spacer()
                
                Button(action: {
                    DispatchQueue.main.async {
                        viewModel.startNewChat()
                    }
                }) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .help("New Chat (⌘N)")
            }
        }
        .navigationTitle(viewModel.currentConversationId != nil ?
            viewModel.conversations.first(where: { $0.id == viewModel.currentConversationId })?.title ?? "Chat" : "New Chat")
        .navigationSubtitle(viewModel.isLoading ? "Thinking..." : "Ready")
    }
    
    private var chatBackground: some View {
        Group {
            if colorScheme == .dark {
                Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0))
            } else {
                Color(nsColor: NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0))
            }
        }
        .ignoresSafeArea()
    }
    
    private func calculateHorizontalPadding(for width: CGFloat) -> CGFloat {
        if width > 1200 { return (width - 900) / 2 }
        else if width > 900 { return (width - 750) / 2 }
        else if width > 700 { return 40 }
        else { return 16 }
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let isLoading: Bool
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            if isLoading {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.blue, .purple, .pink, .purple, .blue],
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 24, height: 24)
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: isLoading ? [.blue, .purple] : [.green, .mint],
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 16, height: 16)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.3), radius: 20, y: 10)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 8) {
                Text("Welcome to Jarvis")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                
                Text("Your AI assistant powered by GPT-5-nano")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 12) {
                Text("Try asking")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    SuggestionChip(text: "Explain a concept", icon: "lightbulb") {
                        viewModel.inputText = "Explain "
                        isInputFocused = true
                    }
                    SuggestionChip(text: "Analyze a file", icon: "doc.text.magnifyingglass") {
                        viewModel.showFilePicker = true
                    }
                    SuggestionChip(text: "Search the web", icon: "globe") {
                        viewModel.inputText = "Search for "
                        isInputFocused = true
                    }
                }
            }
            
            // Keyboard shortcuts hint
            VStack(spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                HStack(spacing: 16) {
                    ShortcutHint(keys: "⌘N", action: "New Chat")
                    ShortcutHint(keys: "⌘,", action: "Settings")
                    ShortcutHint(keys: "⌘K", action: "Focus Input")
                }
            }
            .padding(.top, 20)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShortcutHint: View {
    let keys: String
    let action: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Suggestion Chip
struct SuggestionChip: View {
    let text: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

// MARK: - Messages List View
struct MessagesListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    let containerWidth: CGFloat
    
    private var horizontalPadding: CGFloat {
        if containerWidth > 1200 { return (containerWidth - 900) / 2 }
        else if containerWidth > 900 { return (containerWidth - 750) / 2 }
        else if containerWidth > 700 { return 40 }
        else { return 16 }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages.filter { $0.role != .system }) { message in
                        MessageView(
                            message: message,
                            viewModel: viewModel,
                            isInputFocused: $isInputFocused
                        )
                        .id(message.id)
                    }
                    
                    if viewModel.isLoading && viewModel.messages.last?.role == .user {
                        TypingIndicatorView()
                            .id("typing")
                    }
                    
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 16)
            }
            .scrollIndicators(.automatic)
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isLoading) { _ in
                scrollToBottom(proxy)
            }
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.3)) {
            if viewModel.isLoading {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let lastId = viewModel.messages.filter({ $0.role != .system }).last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

// MARK: - Message View
struct MessageView: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var showBranchConfirm = false
    @State private var isEditing = false
    @State private var editContent = ""
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }
            
            if message.role == .assistant {
                AvatarView(isUser: false)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // File Previews
                if !message.attachedFileNames.isEmpty {
                    FilePreviewRow(
                        fileNames: message.attachedFileNames,
                        fileIds: message.attachedFileIds,
                        isUser: message.role == .user
                    )
                }
                
                // Message Bubble with Markdown
                MessageBubbleContent(
                    message: message,
                    colorScheme: colorScheme,
                    isEditing: $isEditing,
                    editContent: $editContent
                )
                
                // Error Recovery
                if message.isError {
                    ErrorRecoveryView(message: message, viewModel: viewModel)
                }
                
                // Actions
                if !message.isStreaming {
                    MessageActionsView(
                        message: message,
                        viewModel: viewModel,
                        isInputFocused: $isInputFocused,
                        showBranchConfirm: $showBranchConfirm,
                        isEditing: $isEditing,
                        editContent: $editContent
                    )
                }
                
                // Token count for assistant messages
                if message.role == .assistant && message.tokenCount > 0 && !message.isStreaming {
                    Text("\(message.tokenCount) tokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                // Reasoning
                if message.hasReasoning {
                    ReasoningSection(reasoning: message.reasoning)
                }
            }
            .frame(maxWidth: 600, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                AvatarView(isUser: true)
            }
            
            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .confirmationDialog("Create Branch?", isPresented: $showBranchConfirm) {
            Button("Branch from here") {
                viewModel.branchFromMessage(message)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create a new conversation branch from this message.")
        }
    }
}

// MARK: - Message Bubble Content with Markdown
struct MessageBubbleContent: View {
    let message: Message
    let colorScheme: ColorScheme
    @Binding var isEditing: Bool
    @Binding var editContent: String
    
    @ViewBuilder
    private var content: some View {
        if message.isStreaming && message.content.isEmpty {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        } else if isEditing && message.role == .user {
            // Edit mode
            TextEditor(text: $editContent)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 200)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
        } else {
            // Markdown rendering - Use .doc theme which has transparent background
            Markdown(message.content)
                .markdownTheme(.basic)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                        )
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(13)
                        }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }
    
    var body: some View {
        content
            .foregroundStyle(message.role == .user ? .white : (colorScheme == .dark ? .white : .primary))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(bubbleColor)
            )
            .overlay(
                message.isError ?
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.red.opacity(0.5), lineWidth: 2) : nil
            )
    }
    
    private var bubbleColor: Color {
        if message.isError {
            return colorScheme == .dark ? .red.opacity(0.2) : .red.opacity(0.1)
        } else if message.role == .user {
            return Color(red: 0.0, green: 0.48, blue: 1.0)
        } else {
            return colorScheme == .dark ?
                Color(nsColor: NSColor(red: 0.22, green: 0.22, blue: 0.23, alpha: 1.0)) :
                Color(nsColor: NSColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0))
        }
    }
}

// MARK: - File Preview Row
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
                    .font(.caption)
                Text(fileName)
                    .font(.caption)
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
            // Header
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
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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
    }
}

// MARK: - Error Recovery View
struct ErrorRecoveryView: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            
            Text("Something went wrong")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button("Retry") {
                Task { await viewModel.retryFailedMessage(message) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Message Actions View
struct MessageActionsView: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Binding var showBranchConfirm: Bool
    @Binding var isEditing: Bool
    @Binding var editContent: String
    
    var body: some View {
        HStack(spacing: 8) {
            // Copy
            Button(action: { copyContent() }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            if message.role == .user {
                // Edit
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        editContent = ""
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Save & Resend") {
                        isEditing = false
                        Task { await viewModel.editAndResend(message, newContent: editContent) }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: {
                        editContent = message.content
                        isEditing = true
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                // Assistant actions
                
                // Regenerate
                Button(action: {
                    Task { await viewModel.regenerateMessage(message) }
                }) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
                
                // Branch - Only on assistant messages (branch includes this response)
                Button(action: { showBranchConfirm = true }) {
                    Label("Branch", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.bordered)
                
                // Copy Code (if message contains code)
                if message.content.contains("```") {
                    Menu {
                        ForEach(extractCodeBlocks(from: message.content), id: \.self) { code in
                            Button("Copy: \(String(code.prefix(30)))...") {
                                copyToClipboard(code)
                            }
                        }
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.clipboard")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .controlSize(.small)
        .foregroundStyle(.secondary)
    }
    
    private func copyContent() {
        copyToClipboard(message.content)
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func extractCodeBlocks(from content: String) -> [String] {
        let pattern = "```(?:\\w+)?\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        
        return matches.compactMap { match in
            guard let codeRange = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - Avatar View
struct AvatarView: View {
    let isUser: Bool
    
    var body: some View {
        ZStack {
            if isUser {
                Circle()
                    .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Reasoning Section
struct ReasoningSection: View {
    let reasoning: [String]
    @State private var isExpanded = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(reasoning.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(.secondary, in: Circle())
                        
                        Text(reasoning[index])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Reasoning · \(reasoning.count) steps", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }
}

// MARK: - Typing Indicator View
struct TypingIndicatorView: View {
    @State private var animate = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AvatarView(isUser: false)
            
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animate ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ?
                        Color(nsColor: NSColor(red: 0.22, green: 0.22, blue: 0.23, alpha: 1.0)) :
                        Color(nsColor: NSColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0)))
            )
            
            Spacer()
        }
        .onAppear { animate = true }
    }
}

// MARK: - Floating Input Bar
struct FloatingInputBar: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.attachedFiles, id: \.self) { file in
                            AttachmentPill(name: file.lastPathComponent) {
                                viewModel.removeFile(file)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            
            HStack(alignment: .bottom, spacing: 10) {
                Button(action: { viewModel.showFilePicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(viewModel.isLoading ? .gray : .blue)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .fileImporter(
                    isPresented: $viewModel.showFilePicker,
                    allowedContentTypes: [.pdf, .plainText, .image, .png, .jpeg],
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let urls) = result {
                        viewModel.attachFiles(urls)
                    }
                }
                
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .disabled(viewModel.isSending)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .onSubmit { sendMessage() }
                }
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ?
                            Color(nsColor: NSColor(red: 0.18, green: 0.18, blue: 0.2, alpha: 1.0)) :
                            Color(nsColor: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)))
                        .overlay(
                            Capsule().strokeBorder(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 0.5)
                        )
                )
                
                Button(action: {
                    if viewModel.isLoading { viewModel.stopGeneration() }
                    else { sendMessage() }
                }) {
                    Image(systemName: viewModel.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            .white,
                            viewModel.isLoading ? .red : (viewModel.canSend ? Color(red: 0.0, green: 0.48, blue: 1.0) : .gray)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend && !viewModel.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 20, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(colorScheme == .dark ? 0.2 : 0.5), .white.opacity(colorScheme == .dark ? 0.05 : 0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .animation(.spring(response: 0.3), value: viewModel.attachedFiles.count)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
    }
    
    private func sendMessage() {
        guard viewModel.canSend else { return }
        Task {
            await viewModel.sendMessage()
            isInputFocused = true
        }
    }
}

// MARK: - Attachment Pill
struct AttachmentPill: View {
    let name: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .font(.caption)
            Text(name)
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.blue.opacity(0.1), in: Capsule())
        .foregroundStyle(.blue)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ChatViewModel
    @AppStorage("apiBaseURL") private var apiBaseURL = "http://localhost:8000/api"
    @AppStorage("showReasoning") private var showReasoning = true
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("showTokenCount") private var showTokenCount = true
    @AppStorage("showCostEstimate") private var showCostEstimate = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                }
                
                Section("Display") {
                    Toggle("Show AI Reasoning", isOn: $showReasoning)
                    Toggle("Show Token Count", isOn: $showTokenCount)
                    Toggle("Show Cost Estimate", isOn: $showCostEstimate)
                }
                
                Section("Connection") {
                    TextField("API Base URL", text: $apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Session Statistics") {
                    let stats = viewModel.getSessionStats()
                    LabeledContent("Tokens Used", value: "\(stats.tokens)")
                    LabeledContent("Estimated Cost", value: String(format: "$%.6f", stats.cost))
                    
                    Button("Reset Statistics") {
                        viewModel.resetSessionStats()
                    }
                }
                
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Model", value: "GPT-5-nano")
                    LabeledContent("Framework", value: "SwiftUI")
                }
                
                Section("Keyboard Shortcuts") {
                    VStack(alignment: .leading, spacing: 8) {
                        ShortcutRow(keys: "⌘N", action: "New Chat")
                        ShortcutRow(keys: "⌘,", action: "Settings")
                        ShortcutRow(keys: "⌘⇧C", action: "Copy Message")
                        ShortcutRow(keys: "⌃⌘S", action: "Toggle Sidebar")
                        ShortcutRow(keys: "⏎", action: "Send Message")
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .frame(width: 480, height: 550)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct ShortcutRow: View {
    let keys: String
    let action: String
    
    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(action)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .frame(width: 1100, height: 750)
}
