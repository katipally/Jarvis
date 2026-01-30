"""
Knowledge Graph Storage

NetworkX-based knowledge graph for entity-relation storage.
Can be replaced with Neo4j for production use.

Inspired by Cognee's graph memory architecture.
"""

from typing import List, Dict, Any, Optional, Set
from dataclasses import dataclass
import json
from pathlib import Path
from datetime import datetime
import networkx as nx

from .entity_extractor import Entity, Relation
from core.logger import setup_logger
from core.config import settings

logger = setup_logger(__name__)


@dataclass
class GraphQuery:
    """Query result from knowledge graph."""
    entities: List[Entity]
    relations: List[Relation]
    paths: List[List[str]]  # Paths between entities
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "entities": [e.to_dict() for e in self.entities],
            "relations": [r.to_dict() for r in self.relations],
            "paths": self.paths
        }


class KnowledgeGraph:
    """
    In-memory knowledge graph using NetworkX.
    
    Features:
    - Entity and relation storage
    - Graph traversal queries
    - Persistence to JSON
    - Entity deduplication
    """
    
    def __init__(self, persist_path: Optional[str] = None):
        """
        Initialize knowledge graph.
        
        Args:
            persist_path: Path to save/load graph state
        """
        self.graph = nx.DiGraph()
        self.persist_path = persist_path or str(Path(settings.CHROMA_DB_PATH) / "knowledge_graph.json")
        self._load_from_disk()
    
    def _load_from_disk(self):
        """Load graph from disk if exists."""
        try:
            path = Path(self.persist_path)
            if path.exists():
                with open(path, 'r') as f:
                    data = json.load(f)
                
                # Restore nodes (entities)
                for node_data in data.get("nodes", []):
                    node_id = node_data.pop("id")
                    self.graph.add_node(node_id, **node_data)
                
                # Restore edges (relations)
                for edge_data in data.get("edges", []):
                    source = edge_data.pop("source")
                    target = edge_data.pop("target")
                    self.graph.add_edge(source, target, **edge_data)
                
                logger.info(f"Loaded knowledge graph: {self.graph.number_of_nodes()} nodes, {self.graph.number_of_edges()} edges")
        except Exception as e:
            logger.warning(f"Could not load knowledge graph: {e}")
    
    def _save_to_disk(self):
        """Persist graph to disk."""
        try:
            # Serialize nodes
            nodes = []
            for node_id, attrs in self.graph.nodes(data=True):
                nodes.append({"id": node_id, **attrs})
            
            # Serialize edges
            edges = []
            for source, target, attrs in self.graph.edges(data=True):
                edges.append({"source": source, "target": target, **attrs})
            
            data = {"nodes": nodes, "edges": edges}
            
            path = Path(self.persist_path)
            path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(path, 'w') as f:
                json.dump(data, f, indent=2, default=str)
            
            logger.debug(f"Saved knowledge graph to {self.persist_path}")
        except Exception as e:
            logger.error(f"Failed to save knowledge graph: {e}")
    
    def add_entity(self, entity: Entity) -> bool:
        """
        Add or update an entity in the graph.
        
        Args:
            entity: Entity to add
        
        Returns:
            True if new entity, False if updated existing
        """
        is_new = entity.id not in self.graph
        
        self.graph.add_node(
            entity.id,
            name=entity.name,
            entity_type=entity.entity_type,
            properties=entity.properties,
            confidence=entity.confidence,
            source=entity.source,
            created_at=entity.created_at.isoformat(),
            updated_at=datetime.now().isoformat()
        )
        
        self._save_to_disk()
        return is_new
    
    def add_relation(self, relation: Relation) -> bool:
        """
        Add a relation between entities.
        
        Args:
            relation: Relation to add
        
        Returns:
            True if added, False if entities don't exist
        """
        if relation.source_id not in self.graph or relation.target_id not in self.graph:
            logger.warning(f"Cannot add relation: entities not found")
            return False
        
        self.graph.add_edge(
            relation.source_id,
            relation.target_id,
            relation_type=relation.relation_type,
            properties=relation.properties,
            confidence=relation.confidence,
            created_at=relation.created_at.isoformat()
        )
        
        self._save_to_disk()
        return True
    
    def get_entity(self, entity_id: str) -> Optional[Entity]:
        """Get an entity by ID."""
        if entity_id not in self.graph:
            return None
        
        attrs = self.graph.nodes[entity_id]
        return Entity(
            id=entity_id,
            name=attrs.get("name", ""),
            entity_type=attrs.get("entity_type", "concept"),
            properties=attrs.get("properties", {}),
            confidence=attrs.get("confidence", 1.0),
            source=attrs.get("source", "")
        )
    
    def find_entities_by_name(self, name: str, fuzzy: bool = True) -> List[Entity]:
        """
        Find entities by name.
        
        Args:
            name: Name to search for
            fuzzy: Allow partial matches
        """
        results = []
        name_lower = name.lower()
        
        for node_id, attrs in self.graph.nodes(data=True):
            node_name = attrs.get("name", "").lower()
            
            if fuzzy:
                if name_lower in node_name or node_name in name_lower:
                    results.append(self._node_to_entity(node_id, attrs))
            else:
                if name_lower == node_name:
                    results.append(self._node_to_entity(node_id, attrs))
        
        return results
    
    def find_entities_by_type(self, entity_type: str) -> List[Entity]:
        """Find all entities of a given type."""
        results = []
        
        for node_id, attrs in self.graph.nodes(data=True):
            if attrs.get("entity_type") == entity_type:
                results.append(self._node_to_entity(node_id, attrs))
        
        return results
    
    def get_related_entities(
        self,
        entity_id: str,
        relation_types: Optional[List[str]] = None,
        max_depth: int = 2
    ) -> GraphQuery:
        """
        Get entities related to a given entity.
        
        Args:
            entity_id: Starting entity
            relation_types: Filter by relation types
            max_depth: Maximum traversal depth
        
        Returns:
            GraphQuery with related entities and paths
        """
        if entity_id not in self.graph:
            return GraphQuery(entities=[], relations=[], paths=[])
        
        visited: Set[str] = set()
        entities: List[Entity] = []
        relations: List[Relation] = []
        paths: List[List[str]] = []
        
        # BFS traversal
        queue = [(entity_id, [entity_id], 0)]
        
        while queue:
            current_id, path, depth = queue.pop(0)
            
            if current_id in visited or depth > max_depth:
                continue
            
            visited.add(current_id)
            
            # Add entity
            if current_id in self.graph:
                attrs = self.graph.nodes[current_id]
                entities.append(self._node_to_entity(current_id, attrs))
            
            # Explore neighbors
            for neighbor in self.graph.neighbors(current_id):
                edge_data = self.graph.edges[current_id, neighbor]
                rel_type = edge_data.get("relation_type", "related_to")
                
                # Filter by relation type
                if relation_types and rel_type not in relation_types:
                    continue
                
                # Add relation
                relations.append(Relation(
                    id=f"{current_id}_{neighbor}",
                    source_id=current_id,
                    target_id=neighbor,
                    relation_type=rel_type,
                    properties=edge_data.get("properties", {}),
                    confidence=edge_data.get("confidence", 1.0)
                ))
                
                # Add to queue
                new_path = path + [neighbor]
                queue.append((neighbor, new_path, depth + 1))
                
                if depth + 1 <= max_depth:
                    paths.append(new_path)
        
        return GraphQuery(entities=entities, relations=relations, paths=paths)
    
    def search(self, query: str, limit: int = 10) -> List[Entity]:
        """
        Simple text search across entity names and properties.
        
        Args:
            query: Search query
            limit: Maximum results
        
        Returns:
            Matching entities
        """
        query_lower = query.lower()
        results = []
        
        for node_id, attrs in self.graph.nodes(data=True):
            score = 0
            
            # Check name
            name = attrs.get("name", "").lower()
            if query_lower in name:
                score += 2
            elif any(q in name for q in query_lower.split()):
                score += 1
            
            # Check entity type
            entity_type = attrs.get("entity_type", "").lower()
            if query_lower in entity_type:
                score += 0.5
            
            # Check properties
            props = attrs.get("properties", {})
            for v in props.values():
                if isinstance(v, str) and query_lower in v.lower():
                    score += 0.5
                    break
            
            if score > 0:
                results.append((score, self._node_to_entity(node_id, attrs)))
        
        # Sort by score and limit
        results.sort(key=lambda x: x[0], reverse=True)
        return [e for _, e in results[:limit]]
    
    def remove_entity(self, entity_id: str) -> bool:
        """Remove an entity and its relations."""
        if entity_id not in self.graph:
            return False
        
        self.graph.remove_node(entity_id)
        self._save_to_disk()
        return True
    
    def get_stats(self) -> Dict[str, Any]:
        """Get graph statistics."""
        entity_types = {}
        for _, attrs in self.graph.nodes(data=True):
            et = attrs.get("entity_type", "unknown")
            entity_types[et] = entity_types.get(et, 0) + 1
        
        relation_types = {}
        for _, _, attrs in self.graph.edges(data=True):
            rt = attrs.get("relation_type", "unknown")
            relation_types[rt] = relation_types.get(rt, 0) + 1
        
        return {
            "total_entities": self.graph.number_of_nodes(),
            "total_relations": self.graph.number_of_edges(),
            "entity_types": entity_types,
            "relation_types": relation_types
        }
    
    def _node_to_entity(self, node_id: str, attrs: Dict[str, Any]) -> Entity:
        """Convert graph node to Entity object."""
        return Entity(
            id=node_id,
            name=attrs.get("name", ""),
            entity_type=attrs.get("entity_type", "concept"),
            properties=attrs.get("properties", {}),
            confidence=attrs.get("confidence", 1.0),
            source=attrs.get("source", "")
        )


# Singleton instance
knowledge_graph = KnowledgeGraph()
