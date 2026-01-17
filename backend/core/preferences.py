import json
from pathlib import Path
from typing import Dict, Any, Optional
from pydantic import BaseModel
from core.config import settings

class UserPreferences(BaseModel):
    ai_provider: str = "openai"  # "openai" or "ollama"
    openai_model: str = "gpt-5-nano"
    ollama_model: str = "qwen3:8b"
    
    @property
    def current_model(self) -> str:
        if self.ai_provider == "ollama":
            return self.ollama_model
        return self.openai_model

class PreferencesManager:
    def __init__(self):
        # Store preferences in the same directory as chroma_db or a standard config location
        self.pref_file = Path(settings.CHROMA_DB_PATH).parent / "user_preferences.json"
        self._preferences = self._load()

    def _load(self) -> UserPreferences:
        if not self.pref_file.exists():
            return UserPreferences()
        
        try:
            with open(self.pref_file, "r") as f:
                data = json.load(f)
            return UserPreferences(**data)
        except Exception:
            return UserPreferences()

    def save(self, preferences: UserPreferences):
        self._preferences = preferences
        with open(self.pref_file, "w") as f:
            f.write(preferences.model_dump_json(indent=2))

    def get(self) -> UserPreferences:
        # Reload just in case another process changed it (simple consistency)
        self._preferences = self._load()
        return self._preferences

    def update(self, **kwargs) -> UserPreferences:
        current = self.get().model_dump()
        current.update(kwargs)
        new_prefs = UserPreferences(**current)
        self.save(new_prefs)
        return new_prefs

preferences_manager = PreferencesManager()
