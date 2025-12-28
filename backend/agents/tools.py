from typing import List, Dict, Any, Optional
from langchain_core.tools import tool
from core.chroma_client import chroma_client
from services.search_service import search_service
from services.file_processor import file_processor_factory
from pathlib import Path
from core.logger import setup_logger

logger = setup_logger(__name__)


@tool
async def search_knowledge_base(query: str, top_k: int = 5) -> str:
    """
    Search the knowledge base for relevant documents.
    
    Args:
        query: The search query
        top_k: Number of results to return
    
    Returns:
        Formatted string with search results
    """
    try:
        results = await chroma_client.search(query, top_k)
        
        if not results:
            return "No relevant documents found in the knowledge base."
        
        formatted = "## Knowledge Base Results:\n\n"
        for i, result in enumerate(results, 1):
            formatted += f"{i}. {result['document'][:200]}...\n"
            formatted += f"   (Relevance: {1 - result['distance']:.2f})\n\n"
        
        return formatted
    
    except Exception as e:
        logger.error(f"Knowledge base search error: {str(e)}")
        return f"Error searching knowledge base: {str(e)}"


@tool
async def web_search(query: str, max_results: int = 5) -> str:
    """
    Search the internet using DuckDuckGo.
    
    Args:
        query: The search query
        max_results: Maximum number of results
    
    Returns:
        Formatted string with search results
    """
    try:
        results = await search_service.search(query, max_results)
        
        if not results:
            return "No search results found."
        
        formatted = "## Web Search Results:\n\n"
        for i, result in enumerate(results, 1):
            formatted += f"{i}. **{result['title']}**\n"
            formatted += f"   {result['snippet']}\n"
            formatted += f"   URL: {result['url']}\n\n"
        
        return formatted
    
    except Exception as e:
        logger.error(f"Web search error: {str(e)}")
        return f"Error performing web search: {str(e)}"


@tool
async def process_uploaded_file(file_id_or_path: str) -> str:
    """
    Get content from an uploaded file using its file_id or path.
    
    Args:
        file_id_or_path: The file ID (UUID) or file path
    
    Returns:
        The file content extracted from the knowledge base
    """
    try:
        import os
        from core.config import settings
        
        # Check if it's a UUID (file_id) - try to get from ChromaDB first
        try:
            results = await chroma_client.get_documents_by_file_ids([file_id_or_path])
            if results and results.get(file_id_or_path):
                chunks = results[file_id_or_path]
                if chunks:
                    content = "## File Content:\n\n"
                    file_name = chunks[0]["metadata"].get("file_name", file_id_or_path)
                    content += f"**File:** {file_name}\n\n"
                    for i, chunk in enumerate(chunks[:10]):  # Max 10 chunks
                        content += f"**Section {i+1}:**\n{chunk['content']}\n\n"
                    return content
        except Exception as e:
            logger.warning(f"ChromaDB lookup failed: {e}")
        
        # Try as file path - check uploads directory
        upload_dir = Path(settings.UPLOAD_DIR)
        
        # Try to find file by ID in uploads
        for ext in ['.pdf', '.txt', '.png', '.jpg', '.jpeg', '.md']:
            potential_path = upload_dir / f"{file_id_or_path}{ext}"
            if potential_path.exists():
                result = await file_processor_factory.process_file(potential_path)
                if result['success']:
                    return f"## File Content:\n\n**File:** {result['metadata']['file_name']}\n\n{result['text'][:2000]}"
        
        # Try as direct path
        path = Path(file_id_or_path)
        if path.exists():
            result = await file_processor_factory.process_file(path)
            if result['success']:
                return f"## File Content:\n\n**File:** {result['metadata']['file_name']}\n\n{result['text'][:2000]}"
        
        return f"File not found. The file with ID '{file_id_or_path}' may have been uploaded but not yet indexed. Please try asking about the file content directly - it should be available in the context."
    
    except Exception as e:
        logger.error(f"File processing error: {str(e)}")
        return f"Error accessing file: {str(e)}"


def get_tools():
    """Return list of available tools."""
    return [search_knowledge_base, web_search, process_uploaded_file]
