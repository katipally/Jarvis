import Foundation
import GRDB

public struct ScreenFrameRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "screen_frame"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var ts: Date
    public var appBundleId: String?
    public var appName: String?
    public var windowTitle: String?
    public var displayId: Int?
    public var phash: Int64
    public var jpegPath: String
    public var bytes: Int
    public var trigger: String

    public init(id: String = UUID().uuidString, ts: Date = .now, appBundleId: String? = nil,
                appName: String? = nil, windowTitle: String? = nil, displayId: Int? = nil,
                phash: Int64, jpegPath: String, bytes: Int, trigger: String) {
        self.id = id
        self.ts = ts
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.displayId = displayId
        self.phash = phash
        self.jpegPath = jpegPath
        self.bytes = bytes
        self.trigger = trigger
    }
}
