import Foundation

struct Config {
    /// Base URL for the Jarvis API
    /// Prioritizes:
    /// 1. Environment variable "JARVIS_API_URL"
    /// 2. Info.plist key "JarvisAPIURL"
    /// 3. Default localhost
    static var apiBaseURL: String {
        if let envURL = ProcessInfo.processInfo.environment["JARVIS_API_URL"] {
            return envURL
        }
        if let plistURL = Bundle.main.object(forInfoDictionaryKey: "JarvisAPIURL") as? String {
            return plistURL
        }
        return "http://localhost:8000/api"
    }
    
    static var healthCheckURL: String {
        let base = apiBaseURL.replacingOccurrences(of: "/api", with: "")
        return "\(base)/health"
    }
    
    static let maxFileSize: Int64 = 10 * 1024 * 1024
    
    static let supportedFileTypes = [
        "pdf", "txt", "md", "py", "js", "java", "cpp", "c", "h",
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff",
        "docx", "doc"
    ]
}
