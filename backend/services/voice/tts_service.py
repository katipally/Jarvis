"""
Text-to-Speech Service

Supports multiple providers:
- OpenAI TTS (low latency, good quality)
- ElevenLabs (high quality, expressive)
- Chatterbox (optimized for AI agents)
"""

from typing import Optional, AsyncIterator, List
from dataclasses import dataclass
import asyncio
import base64
import re

from .voice_config import TTSConfig
from core.logger import setup_logger
from core.config import settings

logger = setup_logger(__name__)


@dataclass
class AudioChunk:
    """Audio chunk from TTS."""
    data: bytes
    format: str = "mp3"
    sample_rate: int = 24000
    is_final: bool = False
    text_segment: str = ""
    
    def to_base64(self) -> str:
        return base64.b64encode(self.data).decode("utf-8")
    
    def to_dict(self):
        return {
            "data": self.to_base64(),
            "format": self.format,
            "sample_rate": self.sample_rate,
            "is_final": self.is_final,
            "text_segment": self.text_segment,
        }


class TTSService:
    """
    Text-to-speech service with streaming support.
    
    Features:
    - Sentence-by-sentence streaming for low latency
    - Multiple provider support
    - Voice parameter control
    """
    
    def __init__(self, config: Optional[TTSConfig] = None):
        self.config = config or TTSConfig()
    
    async def synthesize(
        self,
        text: str,
        voice: Optional[str] = None,
        speed: Optional[float] = None
    ) -> AudioChunk:
        """
        Synthesize text to audio.
        
        Args:
            text: Text to synthesize
            voice: Override voice
            speed: Override speed
        
        Returns:
            AudioChunk with audio data
        """
        provider = self.config.provider
        voice = voice or self.config.voice
        speed = speed or self.config.speed
        
        if provider == "openai":
            return await self._synthesize_openai(text, voice, speed)
        elif provider == "elevenlabs":
            return await self._synthesize_elevenlabs(text, voice)
        else:
            # Default to OpenAI
            return await self._synthesize_openai(text, voice, speed)
    
    async def stream_synthesis(
        self,
        text: str,
        voice: Optional[str] = None,
        speed: Optional[float] = None
    ) -> AsyncIterator[AudioChunk]:
        """
        Stream TTS synthesis sentence by sentence.
        
        Args:
            text: Full text to synthesize
            voice: Override voice
            speed: Override speed
        
        Yields:
            AudioChunk for each sentence
        """
        # Split text into sentences for streaming
        sentences = self._split_sentences(text)
        
        for i, sentence in enumerate(sentences):
            if not sentence.strip():
                continue
            
            is_final = (i == len(sentences) - 1)
            
            chunk = await self.synthesize(sentence, voice, speed)
            chunk.is_final = is_final
            chunk.text_segment = sentence
            
            yield chunk
    
    def _split_sentences(self, text: str) -> List[str]:
        """Split text into sentences for streaming."""
        # Split on sentence boundaries
        pattern = r'(?<=[.!?])\s+'
        sentences = re.split(pattern, text)
        
        # Handle edge cases
        result = []
        for sentence in sentences:
            sentence = sentence.strip()
            if sentence:
                result.append(sentence)
        
        return result if result else [text]
    
    async def _synthesize_openai(
        self,
        text: str,
        voice: str,
        speed: float
    ) -> AudioChunk:
        """Synthesize using OpenAI TTS."""
        try:
            from openai import AsyncOpenAI
            
            client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
            
            response = await client.audio.speech.create(
                model=self.config.model,
                voice=voice,
                input=text,
                speed=speed,
                response_format=self.config.output_format
            )
            
            # Read the response content
            audio_data = response.content
            
            return AudioChunk(
                data=audio_data,
                format=self.config.output_format,
                sample_rate=self.config.sample_rate,
                text_segment=text
            )
            
        except Exception as e:
            logger.error(f"OpenAI TTS error: {e}")
            return AudioChunk(data=b"", format="mp3", text_segment=text)
    
    async def _synthesize_elevenlabs(
        self,
        text: str,
        voice: str
    ) -> AudioChunk:
        """Synthesize using ElevenLabs API."""
        try:
            import httpx
            
            api_key = self.config.elevenlabs_api_key
            if not api_key:
                raise ValueError("ElevenLabs API key not configured")
            
            # Default voice ID if not specified
            voice_id = voice if len(voice) > 10 else "21m00Tcm4TlvDq8ikWAM"  # Rachel
            
            url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
            
            headers = {
                "Accept": "audio/mpeg",
                "Content-Type": "application/json",
                "xi-api-key": api_key,
            }
            
            data = {
                "text": text,
                "model_id": "eleven_monolingual_v1",
                "voice_settings": {
                    "stability": 0.5,
                    "similarity_boost": 0.75,
                }
            }
            
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    url,
                    json=data,
                    headers=headers,
                    timeout=30.0
                )
                response.raise_for_status()
                audio_data = response.content
            
            return AudioChunk(
                data=audio_data,
                format="mp3",
                sample_rate=self.config.sample_rate,
                text_segment=text
            )
            
        except Exception as e:
            logger.error(f"ElevenLabs TTS error: {e}")
            # Fallback to OpenAI
            return await self._synthesize_openai(text, self.config.voice, self.config.speed)
    
    async def get_available_voices(self) -> List[dict]:
        """Get list of available voices for current provider."""
        provider = self.config.provider
        
        if provider == "openai":
            return [
                {"id": "alloy", "name": "Alloy", "description": "Neutral, balanced"},
                {"id": "echo", "name": "Echo", "description": "Male, warm"},
                {"id": "fable", "name": "Fable", "description": "British, storytelling"},
                {"id": "onyx", "name": "Onyx", "description": "Male, deep"},
                {"id": "nova", "name": "Nova", "description": "Female, young"},
                {"id": "shimmer", "name": "Shimmer", "description": "Female, soft"},
            ]
        elif provider == "elevenlabs":
            try:
                import httpx
                
                api_key = self.config.elevenlabs_api_key
                if not api_key:
                    return []
                
                async with httpx.AsyncClient() as client:
                    response = await client.get(
                        "https://api.elevenlabs.io/v1/voices",
                        headers={"xi-api-key": api_key}
                    )
                    data = response.json()
                    
                return [
                    {"id": v["voice_id"], "name": v["name"], "description": v.get("description", "")}
                    for v in data.get("voices", [])
                ]
            except Exception as e:
                logger.error(f"Failed to get ElevenLabs voices: {e}")
                return []
        
        return []


# Singleton instance
tts_service = TTSService()
