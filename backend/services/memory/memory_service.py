"""
Jarvis Memory Service

Cognee-inspired dual-store memory system combining:
- Knowledge Graph: Entity-relation storage for structured facts
- Vector Store: Semantic embeddings for similarity search
- Session Store: Short-term conversation context

Features:
- remember(): Store facts in both stores
- recall(): Hybrid search (vector + graph)
- forget(): Remove information (privacy)
- consolidate(): End-of-session memory extraction
"""

from typing import List, Dict, Any, Optional
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import asyncio

from .entity_extractor import EntityExtractor, Entity, Relation, entity_extractor
from .knowledge_graph import KnowledgeGraph, knowledge_graph
from core.chroma_client import chroma_client
from core.logger import setup_logger
from agents.state import MemoryContext

logger = setup_logger(__name__)


@dataclass
class MemoryItem:
    """A stored memory item."""
    id: str
    content: str
    memory_type: str  # fact, preference, entity, conversation
    metadata: Dict[str, Any] = field(default_factory=dict)
    embedding_id: Optional[str] = None
    entities: List[str] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.now)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "content": self.content,
            "memory_type": self.memory_type,
            "metadata": self.metadata,
            "entities": self.entities,
            "created_at": self.created_at.isoformat()
        }


class SessionMemory:
    """Short-term session memory."""
    
    def __init__(self, session_id: str, ttl_minutes: int = 60):
        self.session_id = session_id
        self.facts: List[str] = []
        self.entities: List[Entity] = []
        self.topics: List[str] = []
        self.created_at = datetime.now()
        self.ttl_minutes = ttl_minutes
    
    @property
    def is_expired(self) -> bool:
        return datetime.now() > self.created_at + timedelta(minutes=self.ttl_minutes)
    
    def add_fact(self, fact: str):
        if fact not in self.facts:
            self.facts.append(fact)
            # Keep last 20 facts
            if len(self.facts) > 20:
                self.facts = self.facts[-20:]
    
    def add_entity(self, entity: Entity):
        # Avoid duplicates by ID
        existing_ids = {e.id for e in self.entities}
        if entity.id not in existing_ids:
            self.entities.append(entity)
    
    def add_topic(self, topic: str):
        if topic not in self.topics:
            self.topics.append(topic)
            if len(self.topics) > 10:
                self.topics = self.topics[-10:]
    
    def to_memory_context(self) -> MemoryContext:
        return MemoryContext(
            entities=[e.to_dict() for e in self.entities[:10]],
            relations=[],
            relevant_facts=self.facts[:5],
            user_preferences={},
            recent_topics=self.topics[:5]
        )


class MemoryService:
    """
    Unified memory service combining knowledge graph and vector search.
    """
    
    def __init__(
        self,
        extractor: Optional[EntityExtractor] = None,
        graph: Optional[KnowledgeGraph] = None
    ):
        self.extractor = extractor or entity_extractor
        self.graph = graph or knowledge_graph
        self.sessions: Dict[str, SessionMemory] = {}
        
        # Memory collection in ChromaDB
        self.collection_name = "jarvis_memory"
    
    def get_session(self, session_id: str) -> SessionMemory:
        """Get or create a session memory."""
        if session_id not in self.sessions:
            self.sessions[session_id] = SessionMemory(session_id)
        
        session = self.sessions[session_id]
        
        # Check expiry
        if session.is_expired:
            self.sessions[session_id] = SessionMemory(session_id)
        
        return self.sessions[session_id]
    
    async def remember(
        self,
        content: str,
        memory_type: str = "fact",
        metadata: Optional[Dict[str, Any]] = None,
        session_id: Optional[str] = None,
        extract_entities: bool = True
    ) -> MemoryItem:
        """
        Store information in memory.
        
        Args:
            content: Text content to remember
            memory_type: Type of memory (fact, preference, entity, conversation)
            metadata: Additional metadata
            session_id: Optional session for short-term storage
            extract_entities: Whether to extract and store entities
        
        Returns:
            MemoryItem with storage details
        """
        import uuid
        memory_id = str(uuid.uuid4())[:12]
        
        entity_ids = []
        
        # Extract entities if requested
        if extract_entities:
            try:
                entities, relations, facts = await self.extractor.extract(content)
                
                # Store entities in graph
                for entity in entities:
                    self.graph.add_entity(entity)
                    entity_ids.append(entity.id)
                
                # Store relations
                for relation in relations:
                    self.graph.add_relation(relation)
                
                # Add facts to session
                if session_id:
                    session = self.get_session(session_id)
                    for fact in facts:
                        session.add_fact(fact)
                    for entity in entities:
                        session.add_entity(entity)
                
                logger.info(f"Extracted {len(entities)} entities, {len(relations)} relations")
                
            except Exception as e:
                logger.error(f"Entity extraction failed: {e}")
        
        # Store in vector DB for semantic search
        try:
            await chroma_client.add_documents(
                collection_name=self.collection_name,
                documents=[content],
                metadatas=[{
                    "memory_id": memory_id,
                    "memory_type": memory_type,
                    "entities": ",".join(entity_ids),
                    "created_at": datetime.now().isoformat(),
                    **(metadata or {})
                }],
                ids=[memory_id]
            )
        except Exception as e:
            logger.error(f"Vector storage failed: {e}")
        
        return MemoryItem(
            id=memory_id,
            content=content,
            memory_type=memory_type,
            metadata=metadata or {},
            entities=entity_ids,
            embedding_id=memory_id
        )
    
    async def recall(
        self,
        query: str,
        k: int = 5,
        session_id: Optional[str] = None,
        include_graph: bool = True,
        memory_types: Optional[List[str]] = None
    ) -> MemoryContext:
        """
        Retrieve relevant context using hybrid search.
        
        Args:
            query: Search query
            k: Number of results
            session_id: Include session memory if provided
            include_graph: Include knowledge graph traversal
            memory_types: Filter by memory types
        
        Returns:
            MemoryContext with relevant information
        """
        relevant_facts = []
        entities = []
        relations = []
        user_preferences = {}
        recent_topics = []
        
        # 1. Vector similarity search
        try:
            vector_results = await chroma_client.search(
                collection_name=self.collection_name,
                query=query,
                top_k=k
            )
            
            for result in vector_results:
                content = result.get("document", "")
                if content:
                    relevant_facts.append(content)
                
                # Extract preference if applicable
                meta = result.get("metadata", {})
                if meta.get("memory_type") == "preference":
                    key = meta.get("preference_key", "unknown")
                    user_preferences[key] = content
        except Exception as e:
            logger.warning(f"Vector search failed: {e}")
        
        # 2. Knowledge graph search
        if include_graph:
            try:
                # Search for matching entities
                graph_entities = self.graph.search(query, limit=k)
                
                for entity in graph_entities:
                    entities.append(entity.to_dict())
                    
                    # Get related entities
                    related = self.graph.get_related_entities(entity.id, max_depth=1)
                    for rel in related.relations[:5]:
                        relations.append(rel.to_dict())
                    
                    # Extract preferences
                    if entity.entity_type == "preference":
                        user_preferences[entity.name] = entity.properties.get("value", "")
                    
                    # Track topics
                    if entity.entity_type == "concept":
                        recent_topics.append(entity.name)
                        
            except Exception as e:
                logger.warning(f"Graph search failed: {e}")
        
        # 3. Session memory
        if session_id:
            try:
                session = self.get_session(session_id)
                
                # Add session facts
                relevant_facts.extend(session.facts[:3])
                
                # Add session entities
                for entity in session.entities[:5]:
                    entities.append(entity.to_dict())
                
                # Add session topics
                recent_topics.extend(session.topics[:3])
                
            except Exception as e:
                logger.warning(f"Session memory failed: {e}")
        
        # Deduplicate and limit
        relevant_facts = list(dict.fromkeys(relevant_facts))[:k]
        recent_topics = list(dict.fromkeys(recent_topics))[:5]
        
        return MemoryContext(
            entities=entities[:10],
            relations=relations[:10],
            relevant_facts=relevant_facts,
            user_preferences=user_preferences,
            recent_topics=recent_topics
        )
    
    async def forget(
        self,
        entity_id: Optional[str] = None,
        memory_id: Optional[str] = None,
        query: Optional[str] = None
    ) -> bool:
        """
        Remove information from memory (privacy/correction).
        
        Args:
            entity_id: Remove specific entity
            memory_id: Remove specific memory item
            query: Remove memories matching query
        
        Returns:
            True if anything was removed
        """
        removed = False
        
        if entity_id:
            if self.graph.remove_entity(entity_id):
                removed = True
                logger.info(f"Removed entity: {entity_id}")
        
        if memory_id:
            try:
                await chroma_client.delete_documents(
                    collection_name=self.collection_name,
                    ids=[memory_id]
                )
                removed = True
                logger.info(f"Removed memory: {memory_id}")
            except Exception as e:
                logger.warning(f"Failed to remove memory: {e}")
        
        return removed
    
    async def consolidate(
        self,
        session_id: str,
        conversation_messages: List[Dict[str, str]]
    ) -> List[MemoryItem]:
        """
        End-of-session consolidation: extract and store key facts.
        
        Args:
            session_id: Session to consolidate
            conversation_messages: Full conversation history
        
        Returns:
            List of stored memory items
        """
        items = []
        
        try:
            # Extract from full conversation
            entities, relations, facts = await self.extractor.extract_from_conversation(
                conversation_messages
            )
            
            # Store significant entities
            for entity in entities:
                self.graph.add_entity(entity)
            
            # Store relations
            for relation in relations:
                self.graph.add_relation(relation)
            
            # Store facts as memories
            for fact in facts:
                item = await self.remember(
                    content=fact,
                    memory_type="fact",
                    metadata={"session_id": session_id},
                    extract_entities=False  # Already extracted
                )
                items.append(item)
            
            # Clear session
            if session_id in self.sessions:
                del self.sessions[session_id]
            
            logger.info(f"Consolidated session {session_id}: {len(items)} memories stored")
            
        except Exception as e:
            logger.error(f"Consolidation failed: {e}")
        
        return items
    
    async def add_user_preference(
        self,
        key: str,
        value: str,
        session_id: Optional[str] = None
    ) -> Entity:
        """
        Store a user preference.
        
        Args:
            key: Preference key (e.g., "theme", "default_browser")
            value: Preference value
        """
        entity = Entity(
            id=f"pref_{key}",
            name=key,
            entity_type="preference",
            properties={"value": value, "updated_at": datetime.now().isoformat()}
        )
        
        self.graph.add_entity(entity)
        
        # Also store in vector DB for search
        await self.remember(
            content=f"User preference: {key} = {value}",
            memory_type="preference",
            metadata={"preference_key": key, "preference_value": value},
            extract_entities=False
        )
        
        return entity
    
    def get_stats(self) -> Dict[str, Any]:
        """Get memory system statistics."""
        graph_stats = self.graph.get_stats()
        
        return {
            "graph": graph_stats,
            "active_sessions": len(self.sessions),
            "session_ids": list(self.sessions.keys())
        }


# Singleton instance
memory_service = MemoryService()
