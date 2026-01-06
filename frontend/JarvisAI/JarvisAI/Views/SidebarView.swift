import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showSettings: Bool
    @State private var renamingConversation: Conversation?
    @State private var newTitle: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { viewModel.startNewChat() }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Conversations List
            if viewModel.filteredConversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(viewModel.searchText.isEmpty ? "No conversations yet" : "No results found")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding<String?>(
                    get: { viewModel.currentConversationId },
                    set: { id in
                        if let id = id, let conversation = viewModel.conversations.first(where: { $0.id == id }) {
                            viewModel.loadConversation(conversation)
                        }
                    }
                )) {
                    ForEach(groupedConversations, id: \.0) { section, conversations in
                        Section(header: Text(section).font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)) {
                            ForEach(conversations) { conversation in
                                ConversationRow(
                                    conversation: conversation,
                                    isSelected: conversation.id == viewModel.currentConversationId,
                                    onRename: {
                                        renamingConversation = conversation
                                        newTitle = conversation.title
                                    },
                                    onDelete: {
                                        viewModel.deleteConversation(conversation)
                                    }
                                )
                                .tag(conversation.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            
            Divider()
                .padding(.horizontal, 12)
            
            // Footer
            HStack {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gear")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                Spacer()
                
                if viewModel.totalTokensUsed > 0 {
                    Text("\(viewModel.totalTokensUsed) tokens")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .sheet(item: $renamingConversation) { conversation in
            RenameSheet(
                title: $newTitle,
                onSave: {
                    viewModel.renameConversation(conversation, to: newTitle)
                    renamingConversation = nil
                },
                onCancel: {
                    renamingConversation = nil
                }
            )
        }
    }
    
    private var groupedConversations: [(String, [Conversation])] {
        let calendar = Calendar.current
        let now = Date()
        
        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var thisWeek: [Conversation] = []
        var thisMonth: [Conversation] = []
        var older: [Conversation] = []
        
        for conversation in viewModel.filteredConversations {
            if calendar.isDateInToday(conversation.updatedAt) {
                today.append(conversation)
            } else if calendar.isDateInYesterday(conversation.updatedAt) {
                yesterday.append(conversation)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      conversation.updatedAt > weekAgo {
                thisWeek.append(conversation)
            } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now),
                      conversation.updatedAt > monthAgo {
                thisMonth.append(conversation)
            } else {
                older.append(conversation)
            }
        }
        
        var result: [(String, [Conversation])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { result.append(("This Week", thisWeek)) }
        if !thisMonth.isEmpty { result.append(("This Month", thisMonth)) }
        if !older.isEmpty { result.append(("Older", older)) }
        
        return result
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let onRename: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .white : .blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Text(conversation.updatedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct RenameSheet: View {
    @Binding var title: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Conversation")
                .font(.headline)
            
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

