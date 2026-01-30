from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from api.routes import chat, files, health, conversations, conversation, memory, voice
from core.config import settings
from core.logger import setup_logger
from pathlib import Path

logger = setup_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup and shutdown events."""
    # Startup
    logger.info("Starting Jarvis AI Assistant API")
    Path(settings.UPLOAD_DIR).mkdir(exist_ok=True)
    Path(settings.CHROMA_DB_PATH).mkdir(exist_ok=True)
    logger.info(f"Environment: {settings.ENVIRONMENT}")
    logger.info(f"Model: {settings.OPENAI_MODEL}")
    logger.info("API server started successfully")
    
    yield
    
    # Shutdown
    logger.info("Shutting down Jarvis AI Assistant API")


app = FastAPI(
    title="Jarvis AI Assistant API",
    description="Backend API for Jarvis AI Assistant",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.is_development else [],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, tags=["health"])
app.include_router(chat.router, prefix="/api", tags=["chat"])
app.include_router(files.router, prefix="/api", tags=["files"])
app.include_router(conversations.router, tags=["conversations"])
app.include_router(conversation.router, prefix="/api", tags=["conversation"])
app.include_router(memory.router, prefix="/api", tags=["memory"])
app.include_router(voice.router, prefix="/api", tags=["voice"])


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "name": "Jarvis AI Assistant API",
        "version": "1.0.0",
        "status": "running"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.is_development
    )
