import Foundation
import SwiftUI
import Combine

// MARK: - Shared ViewModel Container
/// Singleton container for sharing ChatViewModel across the app
@MainActor
class SharedChatViewModel {
    static let shared = SharedChatViewModel()
    let viewModel: ChatViewModel
    
    private init() {
        viewModel = ChatViewModel()
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var error: String?
    @Published var attachedFiles: [URL] = []
    @Published var uploadedFileIds: [String] = []
    @Published var showFilePicker: Bool = false
    @Published var conversations: [Conversation] = []
    @Published var currentConversationId: String?
    @Published var searchText: String = ""
    
    // Token and cost tracking
    @Published var currentTokenCount: Int = 0
    @Published var sessionCost: Double = 0.0
    @Published var totalTokensUsed: Int = 0
    
    private let streamingService = StreamingService()
    private let storage = ConversationStorage.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentAssistantMessageId: String?
    
    // Computed property to check if can send
    var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasFiles = !attachedFiles.isEmpty
        return (hasText || hasFiles) && !isSending && !isLoading
    }
    
    var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        
        let searchLower = searchText.lowercased()
        return conversations.filter { conversation in
            // Search in title
            if conversation.title.lowercased().contains(searchLower) {
                return true
            }
            // Search in message content (full-text search)
            return conversation.messages.contains { message in
                message.content.lowercased().contains(searchLower)
            }
        }
    }
    
    init() {
        loadConversations()
        setupStreamingObservers()
    }
    
    private func setupStreamingObservers() {
        streamingService.$currentMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                self?.updateAssistantMessage(content: content)
            }
            .store(in: &cancellables)
        
        streamingService.$currentReasoning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reasoning in
                self?.updateAssistantReasoning(reasoning: reasoning)
            }
            .store(in: &cancellables)
        
        streamingService.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStreaming in
                guard let self = self else { return }
                if !isStreaming && self.currentAssistantMessageId != nil {
                    self.finalizeAssistantMessage()
                }
            }
            .store(in: &cancellables)
        
        streamingService.$error
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.handleError(error)
            }
            .store(in: &cancellables)
        
        // Observe token count from streaming service
        streamingService.$tokenCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.currentTokenCount = count
                self?.totalTokensUsed += count
            }
            .store(in: &cancellables)
    }
    
    private func handleError(_ error: String) {
        self.error = error
        self.isLoading = false
        self.isSending = false
        
        if let messageId = currentAssistantMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index] = Message(
                id: messageId,
                role: .assistant,
                content: messages[index].content.isEmpty ? "Error: \(error)" : messages[index].content,
                reasoning: messages[index].reasoning,
                createdAt: messages[index].createdAt,
                isStreaming: false,
                isError: true
            )
            currentAssistantMessageId = nil
        }
    }
    
    private func updateAssistantMessage(content: String) {
        guard let messageId = currentAssistantMessageId,
              let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        messages[index] = Message(
            id: messageId,
            role: .assistant,
            content: content,
            reasoning: messages[index].reasoning,
            createdAt: messages[index].createdAt,
            isStreaming: true,
            attachedFileIds: messages[index].attachedFileIds,
            attachedFileNames: messages[index].attachedFileNames
        )
    }
    
    private func updateAssistantReasoning(reasoning: [String]) {
        guard let messageId = currentAssistantMessageId,
              let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        messages[index] = Message(
            id: messageId,
            role: .assistant,
            content: messages[index].content,
            reasoning: reasoning,
            createdAt: messages[index].createdAt,
            isStreaming: true,
            attachedFileIds: messages[index].attachedFileIds,
            attachedFileNames: messages[index].attachedFileNames
        )
    }
    
    private func finalizeAssistantMessage() {
        guard let messageId = currentAssistantMessageId,
              let index = messages.firstIndex(where: { $0.id == messageId }) else {
            isLoading = false
            isSending = false
            return
        }
        
        // Calculate approximate cost (GPT-5-nano pricing)
        let tokenCost = Double(currentTokenCount) * 0.0000004 // $0.40 per 1M tokens
        sessionCost += tokenCost
        
        messages[index] = Message(
            id: messageId,
            role: .assistant,
            content: messages[index].content,
            reasoning: messages[index].reasoning,
            createdAt: messages[index].createdAt,
            isStreaming: false,
            tokenCount: currentTokenCount,
            attachedFileIds: messages[index].attachedFileIds,
            attachedFileNames: messages[index].attachedFileNames
        )
        
        currentAssistantMessageId = nil
        isLoading = false
        isSending = false
        saveCurrentConversation()
    }
    
    func sendMessage() async {
        guard canSend else { return }
        
        isSending = true
        isLoading = true
        currentTokenCount = 0
        
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filesToUpload = attachedFiles
        let fileNames = attachedFiles.map { $0.lastPathComponent }
        
        let messageText = trimmedText
        inputText = ""
        attachedFiles = []
        
        if currentConversationId == nil {
            createNewConversation()
        }
        
        var fileIds: [String] = []
        if !filesToUpload.isEmpty {
            fileIds = await uploadFiles(filesToUpload)
        }
        
        let userMessage = Message(
            role: .user,
            content: messageText.isEmpty ? "Attached files" : messageText,
            attachedFileIds: fileIds,
            attachedFileNames: fileNames
        )
        messages.append(userMessage)
        
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            reasoning: [],
            createdAt: Date(),
            isStreaming: true
        )
        currentAssistantMessageId = assistantMessage.id
        messages.append(assistantMessage)
        
        await streamingService.sendMessage(messageText, fileIds: fileIds)
    }
    
    // MARK: - Regenerate Message
    func regenerateMessage(_ message: Message) async {
        guard message.role == .assistant,
              let index = messages.firstIndex(where: { $0.id == message.id }),
              index > 0 else { return }
        
        let userMessage = messages[index - 1]
        guard userMessage.role == .user else { return }
        
        // Remove the assistant message
        messages.remove(at: index)
        
        isSending = true
        isLoading = true
        currentTokenCount = 0
        
        // Create new assistant message
        let newAssistantMessage = Message(
            role: .assistant,
            content: "",
            reasoning: [],
            createdAt: Date(),
            isStreaming: true
        )
        currentAssistantMessageId = newAssistantMessage.id
        messages.append(newAssistantMessage)
        
        await streamingService.sendMessage(userMessage.content, fileIds: userMessage.attachedFileIds)
    }
    
    // MARK: - Branch Conversation
    func branchFromMessage(_ message: Message) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        
        // Save current conversation first
        saveCurrentConversation()
        
        // Create new conversation with messages up to and including this one
        let branchedMessages = Array(messages.prefix(through: index))
        
        let newConversation = Conversation()
        var mutableConversation = newConversation
        mutableConversation.messages = branchedMessages
        mutableConversation.title = "Branch: \(conversations.first(where: { $0.id == currentConversationId })?.title ?? "Chat")"
        mutableConversation.updateTitle()
        
        conversations.insert(mutableConversation, at: 0)
        
        // Switch to the new branch
        currentConversationId = mutableConversation.id
        messages = branchedMessages
        
        storage.saveConversations(conversations)
    }
    
    // MARK: - Edit and Resend Message
    func editAndResend(_ message: Message, newContent: String) async {
        guard message.role == .user,
              let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        
        // Remove all messages from this point onwards
        messages.removeSubrange(index...)
        
        // Set input text and send
        inputText = newContent
        await sendMessage()
    }
    
    private func uploadFiles(_ files: [URL]) async -> [String] {
        var uploadedIds: [String] = []
        
        for fileURL in files {
            do {
                guard fileURL.startAccessingSecurityScopedResource() else {
                    continue
                }
                defer { fileURL.stopAccessingSecurityScopedResource() }
                
                let uploadResponse = try await APIService.shared.uploadFile(fileURL: fileURL)
                uploadedIds.append(uploadResponse.fileId)
            } catch {
                print("Failed to upload \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        return uploadedIds
    }
    
    func clearMessages() {
        messages.removeAll()
        attachedFiles = []
        uploadedFileIds = []
        error = nil
    }
    
    func startNewChat() {
        streamingService.cancelStreaming()
        
        if !messages.isEmpty {
            saveCurrentConversationSilently()
        }
        
        // Defer state changes to avoid "Publishing changes from within view updates" warning
        Task { @MainActor in
            messages.removeAll()
            attachedFiles = []
            uploadedFileIds = []
            inputText = ""
            error = nil
            currentConversationId = nil
            currentAssistantMessageId = nil
            isLoading = false
            isSending = false
            currentTokenCount = 0
        }
    }
    
    func attachFiles(_ urls: [URL]) {
        attachedFiles.append(contentsOf: urls)
    }
    
    func removeFile(_ url: URL) {
        attachedFiles.removeAll { $0 == url }
    }
    
    func stopGeneration() {
        streamingService.cancelStreaming()
        isLoading = false
        isSending = false
        
        if let messageId = currentAssistantMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index] = Message(
                id: messageId,
                role: .assistant,
                content: messages[index].content + "\n\n*[Generation stopped]*",
                reasoning: messages[index].reasoning,
                createdAt: messages[index].createdAt,
                isStreaming: false
            )
            currentAssistantMessageId = nil
            saveCurrentConversation()
        }
    }
    
    func retryFailedMessage(_ message: Message) async {
        guard message.isError,
              let index = messages.firstIndex(where: { $0.id == message.id }),
              index > 0 else { return }
        
        await regenerateMessage(message)
    }
    
    func dismissError() {
        error = nil
    }
    
    // MARK: - Conversation Management
    
    private func createNewConversation() {
        let newConversation = Conversation()
        currentConversationId = newConversation.id
        conversations.insert(newConversation, at: 0)
    }
    
    private func saveCurrentConversation() {
        guard let conversationId = currentConversationId,
              let index = conversations.firstIndex(where: { $0.id == conversationId }) else {
            return
        }
        
        var conversation = conversations[index]
        conversation.messages = messages.filter { $0.role != .system }
        conversation.updatedAt = Date()
        conversation.updateTitle()
        conversations[index] = conversation
        
        storage.saveConversations(conversations)
    }
    
    func loadConversation(_ conversation: Conversation) {
        streamingService.cancelStreaming()
        
        // Save current conversation synchronously (doesn't trigger view updates)
        if !messages.isEmpty && currentConversationId != nil {
            saveCurrentConversationSilently()
        }
        
        // Defer state changes to avoid "Publishing changes from within view updates" warning
        // This ensures updates happen outside the view update cycle
        Task { @MainActor in
            currentConversationId = conversation.id
            messages = conversation.messages
            attachedFiles = []
            uploadedFileIds = []
            inputText = ""
            error = nil
            isLoading = false
            isSending = false
            currentAssistantMessageId = nil
        }
    }
    
    // Silent save that doesn't trigger view updates
    private func saveCurrentConversationSilently() {
        guard let conversationId = currentConversationId,
              let index = conversations.firstIndex(where: { $0.id == conversationId }) else {
            return
        }
        
        var conversation = conversations[index]
        conversation.messages = messages.filter { $0.role != .system }
        conversation.updatedAt = Date()
        conversation.updateTitle()
        conversations[index] = conversation
        
        storage.saveConversations(conversations)
    }
    
    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        storage.deleteConversation(id: conversation.id)
        
        if currentConversationId == conversation.id {
            messages.removeAll()
            currentConversationId = nil
            isLoading = false
            isSending = false
        }
    }
    
    func renameConversation(_ conversation: Conversation, to newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            var updated = conversations[index]
            updated.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.updatedAt = Date()
            conversations[index] = updated
            storage.saveConversations(conversations)
        }
    }
    
    private func loadConversations() {
        conversations = storage.loadConversations()
    }
    
    // MARK: - Statistics
    
    func getSessionStats() -> (tokens: Int, cost: Double) {
        return (totalTokensUsed, sessionCost)
    }
    
    func resetSessionStats() {
        totalTokensUsed = 0
        sessionCost = 0.0
    }
}
