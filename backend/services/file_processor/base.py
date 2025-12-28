from abc import ABC, abstractmethod
from typing import Dict, Any, List
from pathlib import Path


class FileProcessor(ABC):
    """Base class for file processors."""
    
    @abstractmethod
    async def process(self, file_path: Path) -> Dict[str, Any]:
        """
        Process a file and extract content.
        
        Returns:
            Dict with keys: text, metadata, chunks, images (optional)
        """
        pass
    
    def chunk_text(self, text: str, chunk_size: int = 1000, overlap: int = 200) -> List[str]:
        """Split text into overlapping chunks."""
        chunks = []
        start = 0
        text_length = len(text)
        
        while start < text_length:
            end = start + chunk_size
            chunk = text[start:end]
            
            if end < text_length:
                last_period = chunk.rfind('.')
                last_newline = chunk.rfind('\n')
                split_point = max(last_period, last_newline)
                
                if split_point > chunk_size // 2:
                    chunk = chunk[:split_point + 1]
                    end = start + split_point + 1
            
            chunks.append(chunk.strip())
            start = end - overlap
        
        return [c for c in chunks if c]
