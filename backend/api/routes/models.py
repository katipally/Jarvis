from fastapi import APIRouter, HTTPException
import httpx
import os
from pydantic import BaseModel
from typing import List, Dict, Any
from core.config import settings

router = APIRouter()

class ModelInfo(BaseModel):
    id: str
    name: str
    provider: str
    can_reason: bool = False

class ModelsResponse(BaseModel):
    openai: List[ModelInfo]
    ollama: List[ModelInfo]

@router.get("/models", response_model=ModelsResponse)
async def get_available_models():
    openai_models = []
    ollama_models = []

    # Fetch OpenAI Models
    if settings.OPENAI_API_KEY:
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    "https://api.openai.com/v1/models",
                    headers={"Authorization": f"Bearer {settings.OPENAI_API_KEY}"},
                    timeout=5.0
                )
                if response.status_code == 200:
                    data = response.json()
                    # Filter for chat models
                    chat_keywords = ["gpt", "o1", "o3", "turbo", "preview"]
                    for model in data.get("data", []):
                        mid = model["id"]
                        if any(k in mid for k in chat_keywords):
                            can_reason = "o1" in mid or "o3" in mid
                            openai_models.append(ModelInfo(
                                id=mid, 
                                name=mid, 
                                provider="openai",
                                can_reason=can_reason
                            ))
        except Exception as e:
            print(f"Error fetching OpenAI models: {e}")

    # Fetch Ollama Models
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "http://localhost:11434/api/tags",
                timeout=2.0
            )
            if response.status_code == 200:
                data = response.json()
                for model in data.get("models", []):
                    mid = model["name"]
                    # Simple heuristic for reasoning models
                    can_reason = "deepseek-r1" in mid or "reason" in mid
                    ollama_models.append(ModelInfo(
                        id=mid, 
                        name=mid, 
                        provider="ollama",
                        can_reason=can_reason
                    ))
    except Exception as e:
        print(f"Error fetching Ollama models: {e}")

    return ModelsResponse(openai=openai_models, ollama=ollama_models)
