from pathlib import Path
from typing import Dict, Any
import pypdf
import fitz
from .base import FileProcessor
from core.logger import setup_logger

logger = setup_logger(__name__)


class PDFProcessor(FileProcessor):
    """Process PDF files with fallback strategies."""
    
    async def process(self, file_path: Path) -> Dict[str, Any]:
        """Extract text and metadata from PDF."""
        try:
            text = await self._extract_with_pypdf(file_path)
            
            if not text or len(text.strip()) < 50:
                logger.info("pypdf extraction minimal, trying pymupdf")
                text = await self._extract_with_pymupdf(file_path)
            
            metadata = {
                "file_type": "pdf",
                "file_name": file_path.name,
                "file_size": file_path.stat().st_size
            }
            
            chunks = self.chunk_text(text)
            
            return {
                "text": text,
                "metadata": metadata,
                "chunks": chunks,
                "success": True
            }
        
        except Exception as e:
            logger.error(f"Error processing PDF {file_path}: {str(e)}")
            return {
                "text": "",
                "metadata": {"error": str(e)},
                "chunks": [],
                "success": False
            }
    
    async def _extract_with_pypdf(self, file_path: Path) -> str:
        """Extract text using pypdf."""
        text_parts = []
        with open(file_path, 'rb') as file:
            pdf = pypdf.PdfReader(file)
            for page in pdf.pages:
                text_parts.append(page.extract_text())
        return "\n".join(text_parts)
    
    async def _extract_with_pymupdf(self, file_path: Path) -> str:
        """Extract text using pymupdf (fallback)."""
        text_parts = []
        doc = fitz.open(file_path)
        for page in doc:
            text_parts.append(page.get_text())
        doc.close()
        return "\n".join(text_parts)
