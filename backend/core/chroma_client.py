import chromadb
from chromadb.config import Settings as ChromaSettings
from typing import List, Dict, Any, Optional
from core.config import settings
from core.logger import setup_logger
from core.openai_client import openai_client
import uuid

logger = setup_logger(__name__)


class ChromaDBClient:
    """
    ChromaDB client with multi-collection support.
    
    Collections:
    - jarvis_knowledge: Primary document/file knowledge base
    - jarvis_memory: Long-term memory storage (facts, preferences)
    - jarvis_conversations: Conversation summaries
    """
    
    def __init__(self):
        self.client = chromadb.PersistentClient(
            path=settings.CHROMA_DB_PATH,
            settings=ChromaSettings(
                anonymized_telemetry=False,
                allow_reset=True
            )
        )
        
        # Default collection for documents
        self.collection = self.client.get_or_create_collection(
            name="jarvis_knowledge",
            metadata={
                "hnsw:space": "cosine",
                "hnsw:construction_ef": 100,
                "hnsw:M": 16
            }
        )
        
        # Memory collection
        self.memory_collection = self.client.get_or_create_collection(
            name="jarvis_memory",
            metadata={
                "hnsw:space": "cosine",
                "hnsw:construction_ef": 100,
                "hnsw:M": 16
            }
        )
        
        logger.info(f"ChromaDB initialized with collections: jarvis_knowledge, jarvis_memory")
    
    def _get_collection(self, collection_name: Optional[str] = None):
        """Get collection by name or return default."""
        if collection_name == "jarvis_memory":
            return self.memory_collection
        elif collection_name:
            return self.client.get_or_create_collection(
                name=collection_name,
                metadata={"hnsw:space": "cosine"}
            )
        return self.collection
    
    async def add_documents(
        self,
        documents: List[str],
        metadatas: List[Dict[str, Any]],
        ids: Optional[List[str]] = None,
        collection_name: Optional[str] = None
    ) -> List[str]:
        """
        Add documents to a collection.
        
        Args:
            documents: Text documents to add
            metadatas: Metadata for each document
            ids: Optional document IDs
            collection_name: Target collection (default: jarvis_knowledge)
        """
        try:
            collection = self._get_collection(collection_name)
            
            if not ids:
                ids = [str(uuid.uuid4()) for _ in documents]
            
            embeddings = []
            for doc in documents:
                embedding = await openai_client.get_embedding(doc)
                embeddings.append(embedding)
            
            collection.add(
                documents=documents,
                embeddings=embeddings,
                metadatas=metadatas,
                ids=ids
            )
            
            logger.info(f"Added {len(documents)} documents to {collection_name or 'jarvis_knowledge'}")
            return ids
        
        except Exception as e:
            logger.error(f"Error adding documents: {str(e)}")
            raise
    
    async def search(
        self,
        query: str,
        top_k: int = 5,
        filter_dict: Optional[Dict[str, Any]] = None,
        collection_name: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Search for relevant documents.
        
        Args:
            query: Search query
            top_k: Number of results
            filter_dict: Optional metadata filter
            collection_name: Target collection (default: jarvis_knowledge)
        """
        try:
            collection = self._get_collection(collection_name)
            query_embedding = await openai_client.get_embedding(query)
            
            params = {
                "query_embeddings": [query_embedding],
                "n_results": top_k,
                "include": ["documents", "metadatas", "distances"]
            }
            
            if filter_dict:
                params["where"] = filter_dict
            
            results = collection.query(**params)
            
            formatted_results = []
            if results['documents'] and results['documents'][0]:
                for i in range(len(results['documents'][0])):
                    formatted_results.append({
                        "document": results['documents'][0][i],
                        "metadata": results['metadatas'][0][i] if results.get('metadatas') else {},
                        "distance": results['distances'][0][i] if results.get('distances') else 0.0
                    })
            
            logger.info(f"Search returned {len(formatted_results)} results from {collection_name or 'jarvis_knowledge'}")
            return formatted_results
        
        except Exception as e:
            logger.error(f"Error searching: {str(e)}")
            raise
    
    async def delete_documents(
        self,
        ids: List[str],
        collection_name: Optional[str] = None
    ) -> bool:
        """
        Delete documents by ID.
        
        Args:
            ids: Document IDs to delete
            collection_name: Target collection
        """
        try:
            collection = self._get_collection(collection_name)
            collection.delete(ids=ids)
            logger.info(f"Deleted {len(ids)} documents from {collection_name or 'jarvis_knowledge'}")
            return True
        except Exception as e:
            logger.error(f"Error deleting documents: {str(e)}")
            return False
    
    async def get_documents_by_file_ids(
        self,
        file_ids: List[str],
        max_chunks_per_file: int = 10
    ) -> Dict[str, List[Dict[str, Any]]]:
        """Retrieve documents by file IDs for context injection."""
        try:
            file_context = {}
            
            for file_id in file_ids:
                try:
                    # Query ChromaDB for documents with this file_id using where filter
                    # First, get all documents with this file_id
                    all_results = self.collection.get(
                        where={"file_id": file_id},
                        include=["documents", "metadatas", "ids"]
                    )
                    
                    if all_results and all_results.get("documents"):
                        chunks = []
                        documents = all_results["documents"]
                        metadatas = all_results.get("metadatas", [])
                        
                        # Limit to max_chunks_per_file
                        for i, doc in enumerate(documents[:max_chunks_per_file]):
                            chunks.append({
                                "content": doc,
                                "metadata": metadatas[i] if i < len(metadatas) else {}
                            })
                        file_context[file_id] = chunks
                        logger.info(f"Retrieved {len(chunks)} chunks for file_id: {file_id}")
                    else:
                        logger.warning(f"No documents found for file_id: {file_id}")
                        file_context[file_id] = []
                except Exception as e:
                    logger.error(f"Error retrieving file_id {file_id}: {str(e)}")
                    file_context[file_id] = []
            
            return file_context
        
        except Exception as e:
            logger.error(f"Error retrieving documents by file_ids: {str(e)}")
            return {}
    
    def get_collection_info(self) -> Dict[str, Any]:
        """Get information about the collection."""
        count = self.collection.count()
        return {
            "name": "jarvis_knowledge",
            "count": count,
            "path": settings.CHROMA_DB_PATH
        }


chroma_client = ChromaDBClient()
