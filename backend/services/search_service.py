import logging
from typing import List, Dict, Any
from ddgs import DDGS

logger = logging.getLogger(__name__)

class SearchService:
    """Internet search using DuckDuckGo."""
    
    def __init__(self):
        self.ddgs = DDGS()
    
    async def search(self, query: str, max_results: int = 5) -> List[Dict[str, Any]]:
        """Search the internet and return results."""
        try:
            results = []
            
            search_results = self.ddgs.text(query, max_results=max_results)
            
            for result in search_results:
                results.append({
                    "title": result.get("title", ""),
                    "url": result.get("href", ""),
                    "snippet": result.get("body", ""),
                    "source": "duckduckgo"
                })
            
            logger.info(f"Search for '{query}' returned {len(results)} results")
            return results
        
        except Exception as e:
            logger.error(f"Search error: {str(e)}")
            return []


search_service = SearchService()
