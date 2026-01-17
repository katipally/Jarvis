import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case serverError(String)
}

actor APIService {
    static let shared = APIService()
    
    private init() {}
    
    func checkHealth() async throws -> Bool {
        guard let url = URL(string: Config.healthCheckURL) else {
            throw APIError.invalidURL
        }
        
        let (_, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        return true
    }
    
    func uploadFile(fileURL: URL) async throws -> FileUploadResponse {
        let uploadURL = URL(string: "\(Config.apiBaseURL)/files/upload")!
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let fileData = try Data(contentsOf: fileURL)
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let uploadResponse = try decoder.decode(FileUploadResponse.self, from: data)
        
        return uploadResponse
    }
    
    func updateAISettings(
        provider: String?, 
        openaiModel: String?, 
        ollamaModel: String?
    ) async throws {
        guard let url = URL(string: "\(Config.apiBaseURL)/settings/ai") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [:]
        if let provider = provider { body["ai_provider"] = provider }
        if let openaiModel = openaiModel { body["openai_model"] = openaiModel }
        if let ollamaModel = ollamaModel { body["ollama_model"] = ollamaModel }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }
    
    func fetchAvailableModels() async throws -> ModelsResponse {
        guard let url = URL(string: "\(Config.apiBaseURL)/models") else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(ModelsResponse.self, from: data)
    }
}

struct ModelsResponse: Codable {
    let openai: [ModelInfo]
    let ollama: [ModelInfo]
}

struct ModelInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String
    let canReason: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, provider
        case canReason = "can_reason"
    }
}

struct FileUploadResponse: Codable {
    let fileId: String
    let fileName: String
    let fileSize: Int
    let fileType: String
    let processed: Bool
    let message: String
    
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileName = "file_name"
        case fileSize = "file_size"
        case fileType = "file_type"
        case processed
        case message
    }
}
