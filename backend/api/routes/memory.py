"""
Jarvis Memory API Routes

REST API for memory operations:
- Search memories (hybrid search)
- Add memories/facts
- Manage user preferences
- Get memory statistics
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from services.memory import memory_service
from core.logger import setup_logger

router = APIRouter()
logger = setup_logger(__name__)


# ============== Request Models ==============

class MemorySearchRequest(BaseModel):
    """Request for memory search."""
    query: str = Field(..., description="Search query")
    k: int = Field(5, description="Number of results", ge=1, le=20)
    session_id: Optional[str] = Field(None, description="Include session memory")
    include_graph: bool = Field(True, description="Include knowledge graph results")
    memory_types: Optional[List[str]] = Field(None, description="Filter by memory types")


class AddMemoryRequest(BaseModel):
    """Request to add a memory."""
    content: str = Field(..., description="Memory content")
    memory_type: str = Field("fact", description="Type: fact, preference, entity, conversation")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Additional metadata")
    session_id: Optional[str] = Field(None, description="Session ID")
    extract_entities: bool = Field(True, description="Extract entities from content")


class UserPreferenceRequest(BaseModel):
    """Request to set a user preference."""
    key: str = Field(..., description="Preference key")
    value: str = Field(..., description="Preference value")
    session_id: Optional[str] = Field(None, description="Session ID")


class ForgetRequest(BaseModel):
    """Request to forget/remove information."""
    entity_id: Optional[str] = Field(None, description="Entity ID to remove")
    memory_id: Optional[str] = Field(None, description="Memory ID to remove")
    query: Optional[str] = Field(None, description="Remove memories matching query")


class ConsolidateRequest(BaseModel):
    """Request to consolidate session memory."""
    session_id: str = Field(..., description="Session ID to consolidate")
    messages: List[Dict[str, str]] = Field(..., description="Conversation messages")


# ============== Routes ==============

@router.get("/memory/search")
async def search_memory(
    query: str,
    k: int = 5,
    session_id: Optional[str] = None,
    include_graph: bool = True
):
    """
    Search memories using hybrid search (vector + graph).
    
    Returns relevant facts, entities, and preferences.
    """
    try:
        context = await memory_service.recall(
            query=query,
            k=k,
            session_id=session_id,
            include_graph=include_graph
        )
        
        return {
            "query": query,
            "results": context.to_dict(),
            "result_count": len(context.relevant_facts)
        }
        
    except Exception as e:
        logger.error(f"Memory search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/memory/search")
async def search_memory_post(request: MemorySearchRequest):
    """Search memories (POST version with more options)."""
    try:
        context = await memory_service.recall(
            query=request.query,
            k=request.k,
            session_id=request.session_id,
            include_graph=request.include_graph,
            memory_types=request.memory_types
        )
        
        return {
            "query": request.query,
            "results": context.to_dict(),
            "result_count": len(context.relevant_facts)
        }
        
    except Exception as e:
        logger.error(f"Memory search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/memory/add")
async def add_memory(request: AddMemoryRequest):
    """
    Add a new memory/fact.
    
    Automatically extracts entities and stores in both vector and graph stores.
    """
    try:
        item = await memory_service.remember(
            content=request.content,
            memory_type=request.memory_type,
            metadata=request.metadata,
            session_id=request.session_id,
            extract_entities=request.extract_entities
        )
        
        return {
            "status": "stored",
            "memory": item.to_dict()
        }
        
    except Exception as e:
        logger.error(f"Add memory error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/memory/preference")
async def set_preference(request: UserPreferenceRequest):
    """Set a user preference."""
    try:
        entity = await memory_service.add_user_preference(
            key=request.key,
            value=request.value,
            session_id=request.session_id
        )
        
        return {
            "status": "stored",
            "preference": {
                "key": request.key,
                "value": request.value,
                "entity_id": entity.id
            }
        }
        
    except Exception as e:
        logger.error(f"Set preference error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/memory")
async def forget_memory(request: ForgetRequest):
    """
    Remove information from memory (privacy/correction).
    """
    try:
        removed = await memory_service.forget(
            entity_id=request.entity_id,
            memory_id=request.memory_id,
            query=request.query
        )
        
        return {
            "status": "removed" if removed else "not_found",
            "entity_id": request.entity_id,
            "memory_id": request.memory_id
        }
        
    except Exception as e:
        logger.error(f"Forget memory error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/memory/consolidate")
async def consolidate_session(request: ConsolidateRequest):
    """
    Consolidate session memory: extract key facts and store long-term.
    
    Call this at the end of a conversation session.
    """
    try:
        items = await memory_service.consolidate(
            session_id=request.session_id,
            conversation_messages=request.messages
        )
        
        return {
            "status": "consolidated",
            "session_id": request.session_id,
            "memories_stored": len(items),
            "memories": [item.to_dict() for item in items]
        }
        
    except Exception as e:
        logger.error(f"Consolidate error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/memory/stats")
async def get_memory_stats():
    """Get memory system statistics."""
    try:
        stats = memory_service.get_stats()
        return stats
        
    except Exception as e:
        logger.error(f"Stats error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/memory/graph/entities")
async def list_graph_entities(
    entity_type: Optional[str] = None,
    limit: int = 50
):
    """List entities in the knowledge graph."""
    try:
        from services.memory import knowledge_graph
        
        if entity_type:
            entities = knowledge_graph.find_entities_by_type(entity_type)
        else:
            entities = []
            for node_id, attrs in list(knowledge_graph.graph.nodes(data=True))[:limit]:
                entities.append(knowledge_graph._node_to_entity(node_id, attrs))
        
        return {
            "entities": [e.to_dict() for e in entities[:limit]],
            "total": len(entities)
        }
        
    except Exception as e:
        logger.error(f"List entities error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/memory/graph/entity/{entity_id}")
async def get_entity(entity_id: str):
    """Get an entity and its relations."""
    try:
        from services.memory import knowledge_graph
        
        entity = knowledge_graph.get_entity(entity_id)
        if not entity:
            raise HTTPException(status_code=404, detail="Entity not found")
        
        related = knowledge_graph.get_related_entities(entity_id, max_depth=1)
        
        return {
            "entity": entity.to_dict(),
            "related": related.to_dict()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Get entity error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
