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

        migrator.registerMigration("v6_hot_indexes") { db in
            try db.create(index: "tool_call_on_run", on: "tool_call", columns: ["run_id"])
            try db.create(index: "run_on_started", on: "run", columns: ["started_at"])
            try db.create(index: "approval_event_on_created", on: "approval_event", columns: ["created_at"])
        }

        migrator.registerMigration("v7_harness") { db in
            try db.alter(table: "message") { t in
                // Compaction flips replaced rows to active=0 (never deletes);
                // kind='summary' rows carry the replacement summary.
                t.add(column: "active", .boolean).notNull().defaults(to: true)
                t.add(column: "kind", .text).notNull().defaults(to: "chat") // chat | summary
            }
            try db.alter(table: "run") { t in
                t.add(column: "cost_usd", .double)
                t.add(column: "total_cache_read_tokens", .integer).notNull().defaults(to: 0)
                t.add(column: "label", .text) // short purpose line for Activity
            }
            try db.drop(table: "compaction_checkpoint") // created in v1, never used
            try db.create(index: "message_on_run", on: "message", columns: ["run_id"])
        }

        // Debounced memory extraction (Hive pattern): pending = user rows with
        // no extracted_at. The partial index is the resume cursor at boot.
        migrator.registerMigration("v8_memory_extraction") { db in
            try db.alter(table: "message") { t in
                t.add(column: "extracted_at", .datetime)
            }
            try db.execute(sql: """
                CREATE INDEX message_pending_extraction ON message(created_at)
                WHERE extracted_at IS NULL AND role = 'user'
                """)
        }

        // Screen Rewind: OCR text on each frame + an FTS5 twin for search.
        migrator.registerMigration("v9_screen_ocr") { db in
            try db.alter(table: "screen_frame") { t in
                t.add(column: "ocr_text", .text)
                t.add(column: "ocr_status", .text).notNull().defaults(to: "pending") // pending | done | skipped
            }
            // Same GRDB synchronize mechanism as memory_fts (v3): triggers keep
            // the index in step through inserts, OCR updates, and TTL deletes.
            try db.create(virtualTable: "screen_frame_fts", using: FTS5()) { t in
                t.synchronize(withTable: "screen_frame")
                t.column("ocr_text")
                t.column("window_title")
                t.tokenizer = .porter(wrapping: .unicode61())
            }
        }

        // Commitments ("you said you'd send X by 3pm") + staged tasks/action items.
        migrator.registerMigration("v10_proactivity_tasks") { db in
            try db.create(table: "commitment") { t in
                t.primaryKey("id", .text)
                t.column("text", .text).notNull()
                t.column("due_at", .datetime)
                t.column("dedupe_key", .text)
                t.column("source_segment_id", .text)
                t.column("status", .text).notNull().defaults(to: "open") // open | notified | done | dismissed
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "commitment_on_due", on: "commitment", columns: ["status", "due_at"])

            try db.create(table: "task") { t in
                t.primaryKey("id", .text)
                t.column("text", .text).notNull()
                t.column("source", .text).notNull()       // chat | meeting | manual
                t.column("source_id", .text)
                t.column("status", .text).notNull().defaults(to: "suggested") // suggested | open | done | dismissed
                t.column("due_at", .datetime)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "task_on_status", on: "task", columns: ["status", "created_at"])
        }

        // Meeting transcription (opt-in): one meeting → many attributed segments.
        migrator.registerMigration("v11_meetings") { db in
            try db.create(table: "meeting") { t in
                t.primaryKey("id", .text)
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("app_bundle_id", .text)
                t.column("title", .text)
                t.column("overview", .text)
                t.column("summary_status", .text).notNull().defaults(to: "pending") // pending | done | skipped
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "meeting_on_started", on: "meeting", columns: ["started_at"])

            try db.create(table: "meeting_segment") { t in
                t.primaryKey("id", .text)
                t.column("meeting_id", .text).notNull()
                    .references("meeting", onDelete: .cascade)
                t.column("ts", .datetime).notNull()
                t.column("source", .text).notNull() // mic | system
                t.column("text", .text).notNull()
            }
            try db.create(index: "meeting_segment_on_meeting", on: "meeting_segment", columns: ["meeting_id", "ts"])
        }

        // Knowledge core rework (fresh start, user-approved): the v3 memory/graph
        // tables are replaced by an episode → fact → entity/edge model with
        // provenance and bi-temporal edges. Old rows are dropped, not migrated —
        // conversations/meetings are re-extracted through the new pipeline on
        // boot (KnowledgeBootstrap). AppDelegate copies jarvis.sqlite to
        // jarvis-pre-v12.sqlite before opening, as insurance.
        migrator.registerMigration("v12_knowledge_core") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS memory_fts")
            try db.execute(sql: "DROP TABLE IF EXISTS memory")
            try db.execute(sql: "DROP TABLE IF EXISTS node_alias")
            try db.execute(sql: "DROP TABLE IF EXISTS graph_edge")
            try db.execute(sql: "DROP TABLE IF EXISTS graph_node")
            try db.execute(sql: "DELETE FROM embedding")

            // A world = one data source with an incremental checkpoint cursor.
            try db.create(table: "world") { t in
                t.primaryKey("id", .text) // chat | meetings | screen | calendar | contacts | mail | imessage | notes | browser | folder:<hash>
                t.column("kind", .text).notNull() // llm_text | structured
                t.column("display_name", .text).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: false)
                t.column("cursor_json", .text)
                t.column("last_sync_at", .datetime)
                t.column("last_status", .text)
                t.column("last_error", .text)
                t.column("created_at", .datetime).notNull()
            }

            // An episode = one raw unit of experience; the provenance root.
            try db.create(table: "episode") { t in
                t.primaryKey("id", .text)
                t.column("world_id", .text).notNull().references("world", onDelete: .cascade)
                t.column("external_id", .text) // source-native id; makes re-syncs idempotent
                t.column("occurred_at", .datetime).notNull()
                t.column("title", .text)
                t.column("content", .text).notNull()
                t.column("extraction_status", .text).notNull().defaults(to: "pending") // pending | done | skipped | failed
                t.column("extracted_at", .datetime)
                t.column("created_at", .datetime).notNull()
                t.uniqueKey(["world_id", "external_id"])
            }
            try db.execute(sql: """
                CREATE INDEX episode_pending ON episode(occurred_at)
                WHERE extraction_status = 'pending'
                """)

            try db.create(table: "fact") { t in
                t.primaryKey("id", .text)
                t.column("episode_id", .text).references("episode")
                t.column("text", .text).notNull()
                t.column("kind", .text).notNull().defaults(to: "raw") // raw | abstract
                t.column("salience", .double).notNull().defaults(to: 0.5)
                t.column("superseded_by", .text).references("fact") // reads filter IS NULL
                t.column("created_at", .datetime).notNull()
            }
            try db.create(virtualTable: "fact_fts", using: FTS5()) { t in
                t.synchronize(withTable: "fact")
                t.column("text")
                t.tokenizer = .porter(wrapping: .unicode61())
            }

            // Entity ids are deterministic (hash of type+norm), so re-ingesting
            // the same thing merges for free. Fuzzy variants become aliases.
            try db.create(table: "entity") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull() // person | org | place | event | topic | project | thing
                t.column("name", .text).notNull()
                t.column("norm", .text).notNull()
                t.column("attrs_json", .text).notNull().defaults(to: "{}")
                t.column("is_self", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.uniqueKey(["type", "norm"])
            }
            try db.create(table: "entity_alias") { t in
                t.column("entity_id", .text).notNull().references("entity", onDelete: .cascade)
                t.column("alias", .text).notNull()
                t.column("alias_norm", .text).notNull()
                t.primaryKey(["entity_id", "alias_norm"])
            }
            try db.create(index: "entity_alias_on_norm", on: "entity_alias", columns: ["alias_norm"])

            // Bi-temporal edges (Graphiti model): valid_from/valid_to = when the
            // fact was true in the world; invalidated_at = when we learned it
            // stopped being true. History is kept, never deleted.
            try db.create(table: "edge") { t in
                t.primaryKey("id", .text)
                t.column("src_id", .text).notNull().references("entity", onDelete: .cascade)
                t.column("dst_id", .text).notNull().references("entity", onDelete: .cascade)
                t.column("rel", .text).notNull() // canonical verb (post-synonym-normalization)
                t.column("confidence", .double).notNull().defaults(to: 0.8)
                t.column("valid_from", .datetime)
                t.column("valid_to", .datetime)
                t.column("created_at", .datetime).notNull()
                t.column("invalidated_at", .datetime)
                t.column("invalidated_by_fact_id", .text).references("fact")
                t.column("superseded_by", .text).references("edge")
                t.column("source_fact_id", .text).references("fact")
                t.column("source_episode_id", .text).references("episode")
                t.column("world_id", .text)
            }
            try db.create(index: "edge_on_src_rel", on: "edge", columns: ["src_id", "rel"])
            try db.create(index: "edge_on_dst", on: "edge", columns: ["dst_id"])
            try db.create(index: "edge_on_invalidated", on: "edge", columns: ["invalidated_at"])
            try db.create(index: "edge_on_source_fact", on: "edge", columns: ["source_fact_id"])

            // One row per world sync — the Activity feed's ingestion entries.
            try db.create(table: "ingest_run") { t in
                t.primaryKey("id", .text)
                t.column("world_id", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("status", .text).notNull() // running | done | empty | error
                t.column("episodes_added", .integer).notNull().defaults(to: 0)
                t.column("facts_added", .integer).notNull().defaults(to: 0)
                t.column("entities_added", .integer).notNull().defaults(to: 0)
                t.column("edges_added", .integer).notNull().defaults(to: 0)
                t.column("error", .text)
            }
            try db.create(index: "ingest_run_on_started", on: "ingest_run", columns: ["started_at"])
        }

        // Decision engine + facet learning (v0.4 M3). Every verdict the engine
        // reaches — including "stayed quiet" — is a decision row; facets are the
        // scored, decaying user-preference model.
        migrator.registerMigration("v13_mind") { db in
            try db.create(table: "decision") { t in
                t.primaryKey("id", .text)
                t.column("ts", .datetime).notNull()
                t.column("kind", .text).notNull() // trigger | heartbeat | delivery | reflection
                t.column("source", .text).notNull() // world id or trigger family
                t.column("trigger_key", .text)
                // deduped | rate_limited | dropped | acknowledged | budget_downgraded |
                // reacted | escalated | notified | suppressed | quiet | noted_fact | task_added
                t.column("action", .text).notNull()
                t.column("reason", .text).notNull()
                t.column("payload_json", .text).notNull().defaults(to: "{}")
                t.column("latency_ms", .integer)
            }
            try db.create(index: "decision_on_ts", on: "decision", columns: ["ts"])

            // Content-key sent-dedup for staged deliveries (heads_up/final_call/…).
            try db.create(table: "delivery_state") { t in
                t.primaryKey("dedupe_key", .text) // stableKey(category|overlapKey|stage)
                t.column("category", .text).notNull()
                t.column("stage", .text).notNull()
                t.column("sent_at", .datetime).notNull()
            }
            try db.create(index: "delivery_state_on_sent", on: "delivery_state", columns: ["sent_at"])

            try db.create(table: "facet") { t in
                t.primaryKey("key", .text) // 'style/verbosity', 'identity/timezone', …
                t.column("class", .text).notNull() // identity | veto | tooling | goal | style | channel
                t.column("value", .text).notNull()
                t.column("state", .text).notNull() // active | provisional | candidate
                t.column("stability", .double).notNull()
                t.column("evidence_count", .integer).notNull().defaults(to: 0)
                t.column("first_seen_at", .datetime).notNull()
                t.column("last_seen_at", .datetime).notNull()
                t.column("user_state", .text).notNull().defaults(to: "auto") // auto | pinned | forgotten
            }

            // Persisted evidence stream (openhuman keeps this in memory; a
            // desktop app must survive relaunch). Source of truth for rebuilds.
            try db.create(table: "facet_evidence") { t in
                t.primaryKey("id", .text)
                t.column("class", .text).notNull()
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("cue", .text).notNull() // explicit | structural | behavioral | recurrence
                t.column("evidence_ref", .text).notNull() // dedup key, e.g. "episode:<id>"
                t.column("observed_at", .datetime).notNull()
                t.column("consumed_at", .datetime)
                t.uniqueKey(["key", "value", "evidence_ref"])
            }
            try db.create(index: "facet_evidence_on_key", on: "facet_evidence", columns: ["key"])
        }

        return migrator
    }
}
