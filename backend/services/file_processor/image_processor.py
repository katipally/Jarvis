from pathlib import Path
from typing import Dict, Any
from PIL import Image
import base64
from io import BytesIO
from .base import FileProcessor
from core.logger import setup_logger
from core.openai_client import openai_client

logger = setup_logger(__name__)


class ImageProcessor(FileProcessor):
    """Process image files using GPT-5 vision."""
    
    async def process(self, file_path: Path) -> Dict[str, Any]:
        """Extract information from images using vision API."""
        try:
            img = Image.open(file_path)
            
            buffered = BytesIO()
            img.save(buffered, format=img.format or "PNG")
            img_base64 = base64.b64encode(buffered.getvalue()).decode()
            
            description = await self._analyze_with_vision(img_base64, img.format or "PNG")
            
            metadata = {
                "file_type": "image",
                "file_name": file_path.name,
                "file_size": file_path.stat().st_size,
                "image_size": f"{img.size[0]}x{img.size[1]}",
                "format": str(img.format)
            }
            
            return {
                "text": description,
                "metadata": metadata,
                "chunks": [description],
                "success": True
            }
        
        except Exception as e:
            logger.error(f"Error processing image {file_path}: {str(e)}")
            return {
                "text": "",
                "metadata": {"error": str(e)},
                "chunks": [],
                "success": False
            }
    
    async def _analyze_with_vision(self, image_base64: str, format: str) -> str:
        """Analyze image using GPT-5 vision."""
        try:
            messages = [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Describe this image in detail. Extract any text visible in the image."
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/{format.lower()};base64,{image_base64}"
                            }
                        }
                    ]
                }
            ]
            
            # Use gpt-4o for vision as it has better vision capabilities
            # GPT-5-nano may not support vision API
            vision_model = "gpt-4o" if "gpt-5" in openai_client.model.lower() else openai_client.model
            
            response = await openai_client.client.chat.completions.create(
                model=vision_model,
                messages=messages,
                max_completion_tokens=1000
            )
            
            return response.choices[0].message.content
        
        except Exception as e:
            logger.error(f"Vision API error: {str(e)}")
            return f"Image file: {format}"
