"""
Entity and Relation Extractor

Uses LLM to extract structured entities and relationships from text.
Inspired by Cognee's entity extraction pipeline.
"""

from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, field
from datetime import datetime
import json
import hashlib
from langchain_openai import ChatOpenAI
from langchain_core.messages import SystemMessage, HumanMessage
from core.config import settings
from core.logger import setup_logger

logger = setup_logger(__name__)


@dataclass
class Entity:
    """An extracted entity."""
    id: str
    name: str
    entity_type: str  # person, place, organization, concept, file, action, etc.
    properties: Dict[str, Any] = field(default_factory=dict)
    confidence: float = 1.0
    source: str = ""  # Where this entity came from
    created_at: datetime = field(default_factory=datetime.now)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "entity_type": self.entity_type,
            "properties": self.properties,
            "confidence": self.confidence,
            "source": self.source,
            "created_at": self.created_at.isoformat()
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Entity":
        return cls(
            id=data.get("id", ""),
            name=data.get("name", ""),
            entity_type=data.get("entity_type", "concept"),
            properties=data.get("properties", {}),
            confidence=data.get("confidence", 1.0),
            source=data.get("source", ""),
            created_at=datetime.fromisoformat(data["created_at"]) if data.get("created_at") else datetime.now()
        )


@dataclass
class Relation:
    """A relationship between two entities."""
    id: str
    source_id: str
    target_id: str
    relation_type: str  # works_at, mentioned_in, related_to, prefers, asked_about, etc.
    properties: Dict[str, Any] = field(default_factory=dict)
    confidence: float = 1.0
    created_at: datetime = field(default_factory=datetime.now)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "source_id": self.source_id,
            "target_id": self.target_id,
            "relation_type": self.relation_type,
            "properties": self.properties,
            "confidence": self.confidence,
            "created_at": self.created_at.isoformat()
        }


EXTRACTION_PROMPT = """You are an entity and relationship extractor. Analyze the conversation and extract:

1. ENTITIES: Named items like people, places, organizations, concepts, files, apps, preferences
2. RELATIONS: Connections between entities

Entity Types:
- person: Named individuals
- place: Locations, addresses
- organization: Companies, institutions
- concept: Abstract ideas, topics discussed
- preference: User preferences (e.g., "prefers dark mode")
- file: Documents, files mentioned
- app: Applications mentioned
- time: Dates, times, schedules
- action: Actions taken or requested

Relation Types:
- works_at: Person works at organization
- located_in: Entity is in a place
- prefers: User preference
- mentioned: Entity mentioned in conversation
- related_to: General relationship
- asked_about: User asked about topic
- used: User used app/tool
- scheduled_for: Event scheduled for time

Output as JSON:
{
  "entities": [
    {"name": "...", "type": "...", "properties": {...}}
  ],
  "relations": [
    {"source": "entity_name", "target": "entity_name", "type": "..."}
  ],
  "facts": [
    "User prefers ...",
    "User mentioned ..."
  ]
}

Focus on extracting USEFUL information that would help personalize future interactions.
Do NOT extract trivial entities like common words or stop words.
"""


class EntityExtractor:
    """Extracts entities and relations from text using LLM."""
    
    def __init__(self):
        self.llm = ChatOpenAI(
            model=settings.OPENAI_FAST_MODEL,
            api_key=settings.OPENAI_API_KEY,
            temperature=0.1
        )
    
    def _generate_id(self, name: str, entity_type: str) -> str:
        """Generate a deterministic ID for an entity."""
        key = f"{entity_type}:{name.lower().strip()}"
        return hashlib.sha256(key.encode()).hexdigest()[:12]
    
    async def extract(
        self,
        text: str,
        context: Optional[str] = None
    ) -> Tuple[List[Entity], List[Relation], List[str]]:
        """
        Extract entities, relations, and facts from text.
        
        Args:
            text: Text to analyze (conversation, message, document)
            context: Optional additional context
        
        Returns:
            Tuple of (entities, relations, facts)
        """
        try:
            # Prepare prompt
            extraction_input = f"TEXT TO ANALYZE:\n{text}"
            if context:
                extraction_input = f"CONTEXT:\n{context}\n\n{extraction_input}"
            
            messages = [
                SystemMessage(content=EXTRACTION_PROMPT),
                HumanMessage(content=extraction_input)
            ]
            
            response = await self.llm.ainvoke(messages)
            
            # Parse response
            content = response.content
            
            # Extract JSON from response
            if "```json" in content:
                content = content.split("```json")[1].split("```")[0]
            elif "```" in content:
                content = content.split("```")[1].split("```")[0]
            
            data = json.loads(content.strip())
            
            # Build entities
            entities = []
            entity_name_to_id = {}
            
            for e in data.get("entities", []):
                entity_id = self._generate_id(e["name"], e.get("type", "concept"))
                entity = Entity(
                    id=entity_id,
                    name=e["name"],
                    entity_type=e.get("type", "concept"),
                    properties=e.get("properties", {}),
                    source="extraction"
                )
                entities.append(entity)
                entity_name_to_id[e["name"].lower()] = entity_id
            
            # Build relations
            relations = []
            for r in data.get("relations", []):
                source_name = r.get("source", "").lower()
                target_name = r.get("target", "").lower()
                
                if source_name in entity_name_to_id and target_name in entity_name_to_id:
                    relation = Relation(
                        id=f"rel_{len(relations)}",
                        source_id=entity_name_to_id[source_name],
                        target_id=entity_name_to_id[target_name],
                        relation_type=r.get("type", "related_to")
                    )
                    relations.append(relation)
            
            # Extract facts
            facts = data.get("facts", [])
            
            logger.info(f"Extracted {len(entities)} entities, {len(relations)} relations, {len(facts)} facts")
            return entities, relations, facts
            
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse extraction response: {e}")
            return [], [], []
        except Exception as e:
            logger.error(f"Entity extraction error: {e}")
            return [], [], []
    
    async def extract_from_conversation(
        self,
        messages: List[Dict[str, str]],
        existing_entities: Optional[List[Entity]] = None
    ) -> Tuple[List[Entity], List[Relation], List[str]]:
        """
        Extract from a conversation history.
        
        Args:
            messages: List of {"role": "user/assistant", "content": "..."}
            existing_entities: Already known entities to avoid duplicates
        """
        # Format conversation for extraction
        conversation_text = ""
        for msg in messages[-10:]:  # Last 10 messages
            role = msg.get("role", "user")
            content = msg.get("content", "")
            conversation_text += f"{role.upper()}: {content}\n"
        
        # Add context about existing entities
        context = None
        if existing_entities:
            known = [f"{e.name} ({e.entity_type})" for e in existing_entities[:10]]
            context = f"Already known entities: {', '.join(known)}"
        
        return await self.extract(conversation_text, context)


# Singleton instance
entity_extractor = EntityExtractor()
