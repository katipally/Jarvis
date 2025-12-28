from fastapi import APIRouter, UploadFile, File, HTTPException
from fastapi.responses import FileResponse
from api.models import FileUploadResponse
from core.config import settings
from core.logger import setup_logger
from services.file_processor import file_processor_factory
from core.chroma_client import chroma_client
from pathlib import Path
import uuid
import aiofiles
import mimetypes

router = APIRouter()
logger = setup_logger(__name__)


@router.post("/files/upload", response_model=FileUploadResponse)
async def upload_file(file: UploadFile = File(...)):
    """Upload and process a file."""
    try:
        if file.size > settings.MAX_FILE_SIZE:
            raise HTTPException(
                status_code=413,
                detail=f"File too large. Max size: {settings.MAX_FILE_SIZE} bytes"
            )
        
        upload_dir = Path(settings.UPLOAD_DIR)
        upload_dir.mkdir(exist_ok=True)
        
        file_id = str(uuid.uuid4())
        file_extension = Path(file.filename).suffix
        file_path = upload_dir / f"{file_id}{file_extension}"
        
        async with aiofiles.open(file_path, 'wb') as f:
            content = await file.read()
            await f.write(content)
        
        result = await file_processor_factory.process_file(file_path)
        
        if result['success'] and result['chunks']:
            metadatas = [
                {
                    **result['metadata'],
                    "chunk_index": i,
                    "file_id": file_id
                }
                for i in range(len(result['chunks']))
            ]
            
            await chroma_client.add_documents(
                documents=result['chunks'],
                metadatas=metadatas
            )
        
        return FileUploadResponse(
            file_id=file_id,
            file_name=file.filename,
            file_size=file.size,
            file_type=result['metadata']['file_type'],
            processed=result['success'],
            message=f"File processed successfully. {len(result['chunks'])} chunks stored."
        )
    
    except Exception as e:
        logger.error(f"File upload error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/files/{file_id}/preview")
async def get_file_preview(file_id: str):
    """Get file preview (for images)."""
    try:
        upload_dir = Path(settings.UPLOAD_DIR)
        
        # Find the file with any extension
        matching_files = list(upload_dir.glob(f"{file_id}.*"))
        if not matching_files:
            raise HTTPException(status_code=404, detail="File not found")
        
        file_path = matching_files[0]
        
        # Determine media type
        media_type, _ = mimetypes.guess_type(str(file_path))
        if media_type is None:
            media_type = "application/octet-stream"
        
        # Only allow image previews
        if not media_type.startswith("image/"):
            raise HTTPException(status_code=400, detail="Preview only available for images")
        
        return FileResponse(
            path=file_path,
            media_type=media_type,
            filename=file_path.name
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"File preview error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/files/{file_id}")
async def get_file_info(file_id: str):
    """Get file information and content from ChromaDB."""
    try:
        file_context = await chroma_client.get_documents_by_file_ids([file_id])
        
        if not file_context or not file_context.get(file_id):
            raise HTTPException(status_code=404, detail="File not found in knowledge base")
        
        chunks = file_context[file_id]
        metadata = chunks[0]["metadata"] if chunks else {}
        
        return {
            "file_id": file_id,
            "file_name": metadata.get("file_name", "Unknown"),
            "file_type": metadata.get("file_type", "Unknown"),
            "chunk_count": len(chunks),
            "content_preview": chunks[0]["content"][:500] if chunks else ""
        }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"File info error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
