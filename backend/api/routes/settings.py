from fastapi import APIRouter, HTTPException
from core.preferences import preferences_manager, UserPreferences
from pydantic import BaseModel

router = APIRouter()

class SettingsUpdateRequest(BaseModel):
    ai_provider: str | None = None
    openai_model: str | None = None
    ollama_model: str | None = None

@router.get("/settings/ai", response_model=UserPreferences)
async def get_ai_settings():
    return preferences_manager.get()

@router.post("/settings/ai", response_model=UserPreferences)
async def update_ai_settings(settings: SettingsUpdateRequest):
    update_data = settings.model_dump(exclude_unset=True)
    return preferences_manager.update(**update_data)
