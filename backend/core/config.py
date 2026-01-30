from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore"
    )
    
    # OpenAI Configuration
    OPENAI_API_KEY: str
    OPENAI_MODEL: str = "gpt-4o"  # Primary reasoning model
    OPENAI_FAST_MODEL: str = "gpt-4o-mini"  # Fast mode model
    EMBEDDING_MODEL: str = "text-embedding-3-small"
    CHROMA_DB_PATH: str = "./chroma_db"
    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"
    MAX_FILE_SIZE: int = 10485760
    UPLOAD_DIR: str = "./uploads"
    
    @property
    def is_development(self) -> bool:
        return self.ENVIRONMENT.lower() == "development"


settings = Settings()
