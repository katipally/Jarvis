import Foundation
import GRDB

/// Single entry point to the local store. One instance per app process.
/// Binary payloads (frames, artifacts) live as files; the DB stores paths.
public final class JarvisDatabase: Sendable {
    public let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Opens (creating if needed) the on-disk database at the given directory.
    public static func open(directory: URL) throws -> JarvisDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("jarvis.sqlite")
        let pool = try DatabasePool(path: url.path)
        return try JarvisDatabase(writer: pool)
    }

    /// In-memory database for tests.
    public static func inMemory() throws -> JarvisDatabase {
        try JarvisDatabase(writer: DatabaseQueue())
    }

    public var reader: any DatabaseReader { writer }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "session") { t in
                t.primaryKey("id", .text)
                t.column("created_at", .datetime).notNull()
                t.column("archived_at", .datetime)
            }

            try db.create(table: "segment") { t in
                t.primaryKey("id", .text)
                t.column("session_id", .text).notNull()
                    .references("session", onDelete: .cascade)
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("title", .text)
                t.column("summary", .text)
                t.column("close_reason", .text) // idle | topic_shift | manual | shutdown
                t.column("extraction_status", .text).notNull().defaults(to: "pending")
            }

            try db.create(table: "run") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull() // foreground | background | cron | nudge
                t.column("segment_id", .text)
                t.column("initiator", .text)
                t.column("status", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("error", .text)
                t.column("total_input_tokens", .integer).notNull().defaults(to: 0)
                t.column("total_output_tokens", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "message") { t in
                t.primaryKey("id", .text)
                t.column("segment_id", .text).notNull()
                    .references("segment", onDelete: .cascade)
                t.column("seq", .integer).notNull()
                t.column("role", .text).notNull() // user | assistant | system | tool
                t.column("status", .text).notNull() // streaming | complete | aborted | error
                t.column("content_json", .text).notNull()
                t.column("run_id", .text)
                t.column("model", .text)
                t.column("provider", .text)
                t.column("input_tokens", .integer)
                t.column("output_tokens", .integer)
                t.column("created_at", .datetime).notNull()
                t.uniqueKey(["segment_id", "seq"])
            }

            try db.create(table: "tool_call") { t in
                t.primaryKey("id", .text)
                t.column("run_id", .text).notNull()
                    .references("run", onDelete: .cascade)
                t.column("message_id", .text)
                t.column("name", .text).notNull()
                t.column("input_json", .text).notNull()
                // pending_approval | approved | denied | running | done | error | repaired
                t.column("state", .text).notNull()
                t.column("output_preview", .text)
                t.column("output_artifact_id", .text)
                t.column("duration_ms", .integer)
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "compaction_checkpoint") { t in
                t.primaryKey("id", .text)
                t.column("segment_id", .text).notNull()
                    .references("segment", onDelete: .cascade)
                t.column("upto_seq", .integer).notNull()
                t.column("summary", .text).notNull()
                t.column("token_estimate", .integer)
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value_json", .text).notNull()
            }

            try db.create(table: "provider_account") { t in
                t.primaryKey("id", .text)
                t.column("provider", .text).notNull() // anthropic | openai | minimax | custom
                t.column("base_url", .text)
                t.column("label", .text)
                t.column("created_at", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2_approvals_artifacts") { db in
            try db.create(table: "approval_rule") { t in
                t.primaryKey("id", .text)
                t.column("tool_name", .text).notNull()
                t.column("scope_key", .text) // NULL = applies to any scope
                t.column("decision", .text).notNull() // allow | deny
                t.column("created_at", .datetime).notNull()
                t.column("expires_at", .datetime)
                t.uniqueKey(["tool_name", "scope_key"])
            }

            try db.create(table: "approval_event") { t in
                t.primaryKey("id", .text)
                t.column("run_id", .text)
                t.column("tool_call_id", .text)
                t.column("tool_name", .text).notNull()
                t.column("summary", .text)
                t.column("allowed", .boolean).notNull()
                t.column("decided_by", .text).notNull() // user | rule | tier_auto | timeout | background
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "artifact") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull() // spill | file | shelf | generated
                t.column("run_id", .text)
                t.column("message_id", .text)
                t.column("path", .text).notNull()
                t.column("filename", .text)
                t.column("mime", .text)
                t.column("bytes", .integer)
                t.column("preview", .text)
                t.column("created_at", .datetime).notNull()
            }
        }

        migrator.registerMigration("v3_memory_graph") { db in
            try db.create(table: "memory") { t in
                t.primaryKey("id", .text)
                t.column("tier", .text).notNull() // short | long
                t.column("kind", .text).notNull() // fact | preference | event | task | insight
                t.column("text", .text).notNull()
                t.column("importance", .double).notNull().defaults(to: 0.5)
                t.column("source_segment_id", .text)
                t.column("status", .text).notNull().defaults(to: "active") // active | superseded | archived
                t.column("superseded_by", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("last_accessed_at", .datetime)
                t.column("access_count", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "memory_on_status_tier", on: "memory", columns: ["status", "tier"])

            // FTS5 index kept in sync with `memory.text` via GRDB-generated triggers.
            try db.create(virtualTable: "memory_fts", using: FTS5()) { t in
                t.synchronize(withTable: "memory")
                t.column("text")
                t.tokenizer = .porter(wrapping: .unicode61())
            }

            try db.create(table: "embedding") { t in
                t.column("owner_kind", .text).notNull() // memory | graph_node
                t.column("owner_id", .text).notNull()
                t.column("model_id", .text).notNull()
                t.column("dim", .integer).notNull()
                t.column("vector", .blob).notNull()
                t.primaryKey(["owner_kind", "owner_id", "model_id"])
            }

            try db.create(table: "graph_node") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull() // person | org | project | place | topic | artifact
                t.column("name", .text).notNull()
                t.column("name_norm", .text).notNull()
                t.column("attrs_json", .text)
                t.column("valid_from", .datetime).notNull()
                t.column("valid_to", .datetime)
                t.column("superseded_by", .text)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "graph_node_on_norm", on: "graph_node", columns: ["name_norm"])

            try db.create(table: "graph_edge") { t in
                t.primaryKey("id", .text)
                t.column("src_id", .text).notNull().references("graph_node", onDelete: .cascade)
                t.column("dst_id", .text).notNull().references("graph_node", onDelete: .cascade)
                t.column("relation", .text).notNull()
                t.column("attrs_json", .text)
                t.column("weight", .double).notNull().defaults(to: 1.0)
                t.column("source_memory_id", .text)
                t.column("valid_from", .datetime).notNull()
                t.column("valid_to", .datetime)
                t.column("superseded_by", .text)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "graph_edge_on_src", on: "graph_edge", columns: ["src_id"])
            try db.create(index: "graph_edge_on_dst", on: "graph_edge", columns: ["dst_id"])

            try db.create(table: "node_alias") { t in
                t.column("node_id", .text).notNull().references("graph_node", onDelete: .cascade)
                t.column("alias", .text).notNull()
                t.column("alias_norm", .text).notNull()
                t.primaryKey(["node_id", "alias_norm"])
            }
            try db.create(index: "node_alias_on_norm", on: "node_alias", columns: ["alias_norm"])
        }

        migrator.registerMigration("v4_screen_frames") { db in
            try db.create(table: "screen_frame") { t in
                t.primaryKey("id", .text)
                t.column("ts", .datetime).notNull()
                t.column("app_bundle_id", .text)
                t.column("app_name", .text)
                t.column("window_title", .text)
                t.column("display_id", .integer)
                t.column("phash", .integer).notNull() // 64-bit average hash
                t.column("jpeg_path", .text).notNull()
                t.column("bytes", .integer).notNull()
                t.column("trigger", .text).notNull() // context_switch | tick | on_demand
            }
            try db.create(index: "screen_frame_on_ts", on: "screen_frame", columns: ["ts"])
            try db.create(index: "screen_frame_on_app_ts", on: "screen_frame", columns: ["app_bundle_id", "ts"])
        }

        migrator.registerMigration("v5_proactivity") { db in
            try db.create(table: "cron_job") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("cron_expr", .text).notNull()
                t.column("prompt", .text).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("last_run_at", .datetime)
                t.column("next_run_at", .datetime).notNull()
                t.column("last_status", .text)
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "heartbeat_state") { t in
                t.column("id", .integer).primaryKey()
                t.column("last_run_at", .datetime)
                t.column("last_result", .text)
            }

            try db.create(table: "nudge") { t in
                t.primaryKey("id", .text)
                t.column("created_at", .datetime).notNull()
                t.column("trigger", .text).notNull() // context_switch | cron | heartbeat | agent
                t.column("frame_id", .text)
                t.column("dedup_key", .text)
                t.column("title", .text)
                t.column("body", .text).notNull()
                t.column("state", .text).notNull().defaults(to: "shown") // shown | opened | dismissed
            }
            try db.create(index: "nudge_on_created", on: "nudge", columns: ["created_at"])
        }

        return migrator
    }
}
