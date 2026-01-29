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
