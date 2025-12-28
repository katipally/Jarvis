from fastapi import APIRouter
from api.models import HealthResponse
from core.chroma_client import chroma_client
from core.cost_tracker import cost_tracker

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    chroma_info = chroma_client.get_collection_info()
    
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        chroma_db=chroma_info
    )


@router.get("/stats/cost")
async def get_cost_stats():
    """Get cost tracking statistics."""
    return cost_tracker.get_stats()
