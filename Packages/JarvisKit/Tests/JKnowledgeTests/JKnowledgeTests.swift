import Foundation
import GRDB
import Testing
@testable import JKnowledge
@testable import JStore

private func makeStore() throws -> (KnowledgeStore, JarvisDatabase) {
    let db = try JarvisDatabase.inMemory()
    return (KnowledgeStore(database: db), db)
}

// MARK: - EntityResolver

@Suite struct EntityResolverTests {
    @Test func normCollapsesVariants() {
        #expect(EntityResolver.normName("New York") == EntityResolver.normName("new-york"))
        #expect(EntityResolver.normName("New York") == EntityResolver.normName("NewYork"))
        #expect(EntityResolver.normName("Café") == EntityResolver.normName("café"))
        #expect(EntityResolver.normName("!!!").isEmpty)
    }

    @Test func deterministicIDIsStable() {
        let a = EntityResolver.deterministicID(type: .person, norm: "yash")
        let b = EntityResolver.deterministicID(type: .person, norm: "yash")
        let c = EntityResolver.deterministicID(type: .org, norm: "yash")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hasPrefix("ent_"))
    }

    @Test func jaroWinklerCatchesTypos() {
        #expect(EntityResolver.jaroWinkler("google", "googel") >= 0.94)
        #expect(EntityResolver.jaroWinkler("google", "apple") < 0.94)
        #expect(EntityResolver.jaroWinkler("same", "same") == 1)
    }

    @Test func guardrailsBlockBadMerges() {
        // differing numeric tokens never merge
        #expect(!EntityResolver.canMerge("m1", "m2"))
        #expect(!EntityResolver.canMerge("adr-11", "adr-13"))
        // big length gap never merges
        #expect(!EntityResolver.canMerge("sam", "samuel jackson"))
        // benign variants pass
        #expect(EntityResolver.canMerge("google", "googel"))
    }

    @Test func resolvesFuzzyVariantInDB() async throws {
        let (store, db) = try makeStore()
        _ = await store.ingest(KnowledgeExtractionResult(
            entities: [ExtractedEntity(name: "Google", type: .org)]), episode: nil)
        let resolved = try await db.reader.read { db in
            try EntityResolver.resolveExisting(db, name: "Googel", type: .org)
        }
        #expect(resolved != nil)
        // Same name, different type → distinct entity
        let wrongType = try await db.reader.read { db in
            try EntityResolver.resolveExisting(db, name: "Googel", type: .person)
        }
        #expect(wrongType == nil)
    }
}

// MARK: - Relations

@Suite struct RelationsTests {
    @Test func synonymsCollapse() {
        #expect(Relations.normalize("resides in") == "lives_in")
        #expect(Relations.normalize("Moved-To") == "lives_in")
        #expect(Relations.normalize("employed_by") == "works_at")
        #expect(Relations.normalize("loves") == "likes")
        #expect(Relations.normalize("unknown_verb") == "unknown_verb")
    }

    @Test func functionalSet() {
        #expect(Relations.isFunctional("lives_in"))
        #expect(Relations.isFunctional("works_at"))
        #expect(!Relations.isFunctional("likes"))
        #expect(!Relations.isFunctional("knows"))
    }
}

// MARK: - GraphWriter / supersession

@Suite struct GraphWriterTests {
    @Test func functionalRelationSupersedes() async throws {
        let (store, db) = try makeStore()
        // "I moved to Austin" … later … "actually I moved to Denver"
        _ = await store.ingest(KnowledgeExtractionResult(
            facts: [ExtractedFact(text: "Me lives in Austin and enjoys the food scene there")],
            entities: [ExtractedEntity(name: "Austin", type: .place)],
            relations: [ExtractedRelation(subject: "Me", relation: "moved_to", object: "Austin")]),
            episode: nil)
        _ = await store.ingest(KnowledgeExtractionResult(
            facts: [ExtractedFact(text: "Me lives in Denver after relocating from Austin recently")],
            entities: [ExtractedEntity(name: "Denver", type: .place)],
            relations: [ExtractedRelation(subject: "Me", relation: "lives_in", object: "Denver")]),
            episode: nil)

        let (live, dead) = try await db.reader.read { db -> ([EdgeRow], [EdgeRow]) in
            let all = try EdgeRow.filter(Column("rel") == "lives_in").fetchAll(db)
            return (all.filter { $0.invalidatedAt == nil }, all.filter { $0.invalidatedAt != nil })
        }
        #expect(live.count == 1)
        #expect(dead.count == 1)
        // history kept: the dead edge points at its replacement
        #expect(dead.first?.supersededBy == live.first?.id)
        // the stale fact is superseded by the new one (Hive DATA-1)
        let staleFacts = try await db.reader.read { db in
            try FactRow.filter(Column("superseded_by") != nil).fetchAll(db)
        }
        #expect(staleFacts.contains { $0.text.contains("Austin") })
    }

    @Test func invalidationWithoutReplacement() async throws {
        let (store, db) = try makeStore()
        _ = await store.ingest(KnowledgeExtractionResult(
            entities: [ExtractedEntity(name: "Acme", type: .org)],
            relations: [ExtractedRelation(subject: "Me", relation: "works_at", object: "Acme")]),
            episode: nil)
        _ = await store.ingest(KnowledgeExtractionResult(
            invalidations: [ExtractedRelation(subject: "Me", relation: "works_at", object: "")]),
            episode: nil)

        let live = try await db.reader.read { db in
            try EdgeRow.filter(Column("rel") == "works_at" && Column("invalidated_at") == nil).fetchCount(db)
        }
        #expect(live == 0)
    }

    @Test func selfAliasesCollapseToOneNode() async throws {
        let (store, db) = try makeStore()
        _ = await store.ingest(KnowledgeExtractionResult(
            entities: [ExtractedEntity(name: "Jarvis Project", type: .project)],
            relations: [
                ExtractedRelation(subject: "Me", relation: "works_on", object: "Jarvis Project"),
                ExtractedRelation(subject: "the user", relation: "uses", object: "Jarvis Project"),
            ]), episode: nil)
        let selfNodes = try await db.reader.read { db in
            try EntityRow.filter(Column("is_self") == true).fetchAll(db)
        }
        #expect(selfNodes.count == 1)
        let edges = try await db.reader.read { db in
            try EdgeRow.fetchAll(db)
        }
        #expect(edges.allSatisfy { $0.srcId == selfNodes.first?.id })
    }

    @Test func numericVariantsStayDistinct() async throws {
        let (store, db) = try makeStore()
        _ = await store.ingest(KnowledgeExtractionResult(entities: [
            ExtractedEntity(name: "M1", type: .thing),
            ExtractedEntity(name: "M2", type: .thing),
        ]), episode: nil)
        let count = try await db.reader.read { db in try EntityRow.fetchCount(db) }
        #expect(count == 2)
    }
}

// MARK: - Ingest dedup + episodes

@Suite struct IngestTests {
    @Test func exactAndJaccardDedup() async throws {
        let (store, _) = try makeStore()
        let fact = "Yash is building a macOS notch assistant called Jarvis"
        let c1 = await store.ingest(KnowledgeExtractionResult(facts: [ExtractedFact(text: fact)]), episode: nil)
        #expect(c1.facts == 1)
        // exact dup
        let c2 = await store.ingest(KnowledgeExtractionResult(facts: [ExtractedFact(text: fact)]), episode: nil)
        #expect(c2.facts == 0)
        // token-overlap paraphrase (same tokens, reordered)
        let c3 = await store.ingest(KnowledgeExtractionResult(
            facts: [ExtractedFact(text: "Yash is building Jarvis, a macOS notch assistant")]), episode: nil)
        #expect(c3.facts == 0)
    }

    @Test func validatorGatesJunk() async throws {
        let (store, _) = try makeStore()
        let counts = await store.ingest(KnowledgeExtractionResult(facts: [
            ExtractedFact(text: "Can you hear me?"),
            ExtractedFact(text: "User is engaging with Jarvis, a Mac assistant."),
        ]), episode: nil)
        #expect(counts.facts == 0)
        // explicit remember bypasses the gate
        let forced = await store.ingest(KnowledgeExtractionResult(
            facts: [ExtractedFact(text: "Call mom Friday")]), episode: nil, bypassValidation: true)
        #expect(forced.facts == 1)
    }

    @Test func episodeIdempotency() async throws {
        let (store, _) = try makeStore()
        await store.ensureWorld(id: "mail", kind: "llm_text", displayName: "Mail", enabled: true)
        let first = try await store.addEpisode(worldId: "mail", externalId: "msg-1", occurredAt: .now, content: "Email body")
        #expect(first != nil)
        let dup = try await store.addEpisode(worldId: "mail", externalId: "msg-1", occurredAt: .now, content: "Email body again")
        #expect(dup == nil)
    }

    @Test func pendingQueueAndMark() async throws {
        let (store, _) = try makeStore()
        await store.ensureWorld(id: "chat", kind: "llm_text", displayName: "Chat", enabled: true)
        let ep = try await store.addEpisode(worldId: "chat", occurredAt: .now, content: "Hello world episode")
        #expect(await store.pendingEpisodes().count == 1)
        await store.markEpisode(id: ep!.id, status: "done")
        #expect(await store.pendingEpisodes().isEmpty)
    }

    @Test func invalidationSupersedesStoredFact() async throws {
        // The remember() shape: fact stored in one round, edge added in a
        // later round (fact dedupes there), then an invalidation arrives.
        let (store, db) = try makeStore()
        _ = await store.ingest(KnowledgeExtractionResult(
            facts: [ExtractedFact(text: "Me works at Acme as a senior engineer")]), episode: nil)
        _ = await store.ingest(KnowledgeExtractionResult(
            facts: [ExtractedFact(text: "Me works at Acme as a senior engineer")], // dedupes
            entities: [ExtractedEntity(name: "Acme", type: .org)],
            relations: [ExtractedRelation(subject: "Me", relation: "works_at", object: "Acme")]),
            episode: nil)
        _ = await store.ingest(KnowledgeExtractionResult(
            invalidations: [ExtractedRelation(subject: "Me", relation: "works_at", object: "Acme")]),
            episode: nil)

        let liveEdges = try await db.reader.read { db in
            try EdgeRow.filter(Column("rel") == "works_at" && Column("invalidated_at") == nil).fetchCount(db)
        }
        #expect(liveEdges == 0)
        // The stale fact must be out of retrieval too, not just the edge.
        let hits = await store.retrieve(query: "works at Acme")
        #expect(!hits.contains { $0.text.contains("Acme") })
    }
}

// MARK: - Retrieval + traversal

@Suite struct RetrievalTests {
    @Test func lexicalRetrievalFindsFacts() async throws {
        let (store, _) = try makeStore()
        _ = await store.ingest(KnowledgeExtractionResult(facts: [
            ExtractedFact(text: "Yash lives in Denver near the mountains"),
            ExtractedFact(text: "Yash works on a Swift project called Jarvis"),
        ]), episode: nil)
        let hits = await store.retrieve(query: "where does Yash live")
        #expect(hits.contains { $0.text.contains("Denver") })
    }

    @Test func supersededFactsExcluded() async throws {
        let (store, _) = try makeStore()
        _ = await store.ingest(KnowledgeExtractionResult(
            facts: [ExtractedFact(text: "Yash prefers tabs over spaces in every editor")]), episode: nil)
        let id = (await store.list()).first!.id
        await store.archive(id: id)
        let hits = await store.retrieve(query: "tabs spaces editor")
        #expect(hits.isEmpty)
        #expect(await store.list().isEmpty)
    }

    @Test func graphContextTraversesButAvoidsHubs() async throws {
        let (store, db) = try makeStore()
        // Me -> works_at -> Acme; Acme -> located_in -> Austin (2 hops from "me")
        _ = await store.ingest(KnowledgeExtractionResult(
            entities: [
                ExtractedEntity(name: "Acme", type: .org),
                ExtractedEntity(name: "Austin", type: .place),
            ],
            relations: [
                ExtractedRelation(subject: "Me", relation: "works_at", object: "Acme"),
                ExtractedRelation(subject: "Acme", relation: "located_in", object: "Austin"),
            ]), episode: nil)
        let lines = try await db.reader.read { db in
            try Traverse.graphFacts(db, query: "acme")
        }
        #expect(lines.contains { $0.contains("works at") })
        #expect(lines.contains { $0.contains("located in") })
    }
}

// MARK: - FactValidator

@Suite struct FactValidatorTests {
    @Test func jaccardOverlap() {
        let a = "Yash is building a macOS notch assistant called Jarvis"
        #expect(FactValidator.jaccard(a, a) == 1)
        #expect(FactValidator.jaccard(a, "completely different words entirely") < 0.2)
    }

    @Test func selfReferencesAreNotRejectedEntities() {
        #expect(FactValidator.isRealEntity("Me")) // handled by GraphWriter, not rejected
        #expect(!FactValidator.isRealEntity("Jarvis"))
        #expect(!FactValidator.isRealEntity("the assistant"))
    }
}
