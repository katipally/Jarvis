from pathlib import Path
from typing import Dict, Any
from .pdf_processor import PDFProcessor
from .image_processor import ImageProcessor
from .document_processor import DocumentProcessor
from core.logger import setup_logger

logger = setup_logger(__name__)


class FileProcessorFactory:
    """Factory to route files to appropriate processors."""
    
    def __init__(self):
        self.processors = {
            'pdf': PDFProcessor(),
            'image': ImageProcessor(),
            'document': DocumentProcessor()
        }
    
    def get_processor_type(self, file_path: Path) -> str:
        """Determine which processor to use based on file extension."""
        extension = file_path.suffix.lower()
        
        if extension == '.pdf':
            return 'pdf'
        elif extension in ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tiff']:
            return 'image'
        else:
            return 'document'
    
    async def process_file(self, file_path: Path) -> Dict[str, Any]:
        """Process file using appropriate processor."""
        processor_type = self.get_processor_type(file_path)
        processor = self.processors[processor_type]
        
        logger.info(f"Processing {file_path.name} with {processor_type} processor")
        result = await processor.process(file_path)
        
        return result


file_processor_factory = FileProcessorFactory()
