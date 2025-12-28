import Foundation

struct Config {
    static let apiBaseURL = "http://localhost:8000/api"
    static let healthCheckURL = "http://localhost:8000/health"
    
    static let maxFileSize: Int64 = 10 * 1024 * 1024
    
    static let supportedFileTypes = [
        "pdf", "txt", "md", "py", "js", "java", "cpp", "c", "h",
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff",
        "docx", "doc"
    ]
}
