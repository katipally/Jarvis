"""
Speech-to-Text Service

Supports multiple providers:
- Deepgram (streaming, high accuracy)
- OpenAI Whisper (offline capable)
- Apple Speech Framework (fallback)
"""

from typing import Optional, AsyncIterator, Callable, Any
from dataclasses import dataclass
import asyncio
import base64
import json
import os

from .voice_config import STTConfig
from core.logger import setup_logger
from core.config import settings

logger = setup_logger(__name__)


@dataclass
class TranscriptResult:
    """Result from speech-to-text."""
    text: str
    is_final: bool
    confidence: float = 1.0
    start_time: float = 0.0
    end_time: float = 0.0
    words: list = None
    
    def to_dict(self):
        return {
            "text": self.text,
            "is_final": self.is_final,
            "confidence": self.confidence,
            "start_time": self.start_time,
            "end_time": self.end_time,
        }


class STTService:
    """
    Speech-to-text service with multiple provider support.
    
    Features:
    - Streaming transcription
    - Interim results
    - Multi-provider fallback
    """
    
    def __init__(self, config: Optional[STTConfig] = None):
        self.config = config or STTConfig()
        self._deepgram_client = None
        self._whisper_model = None
    
    async def transcribe_audio(
        self,
        audio_data: bytes,
        sample_rate: int = 16000,
        encoding: str = "linear16"
    ) -> TranscriptResult:
        """
        Transcribe audio bytes to text.
        
        Args:
            audio_data: Raw audio bytes
            sample_rate: Audio sample rate
            encoding: Audio encoding format
        
        Returns:
            TranscriptResult with transcription
        """
        provider = self.config.provider
        
        if provider == "deepgram":
            return await self._transcribe_deepgram(audio_data, sample_rate)
        elif provider == "whisper":
            return await self._transcribe_whisper(audio_data)
        elif provider == "openai":
            return await self._transcribe_openai_whisper(audio_data)
        else:
            # Fallback to OpenAI
            return await self._transcribe_openai_whisper(audio_data)
    
    async def stream_transcription(
        self,
        audio_stream: AsyncIterator[bytes],
        on_transcript: Callable[[TranscriptResult], Any]
    ) -> None:
        """
        Stream transcription from audio chunks.
        
        Args:
            audio_stream: Async iterator of audio chunks
            on_transcript: Callback for transcript results
        """
        provider = self.config.provider
        
        if provider == "deepgram":
            await self._stream_deepgram(audio_stream, on_transcript)
        else:
            # Buffer and transcribe for non-streaming providers
            await self._stream_buffered(audio_stream, on_transcript)
    
    async def _transcribe_deepgram(
        self,
        audio_data: bytes,
        sample_rate: int
    ) -> TranscriptResult:
        """Transcribe using Deepgram API."""
        try:
            import httpx
            
            api_key = self.config.deepgram_api_key
            if not api_key:
                raise ValueError("Deepgram API key not configured")
            
            url = "https://api.deepgram.com/v1/listen"
            params = {
                "model": self.config.model,
                "language": self.config.language,
                "punctuate": str(self.config.enable_punctuation).lower(),
                "encoding": "linear16",
                "sample_rate": str(sample_rate),
            }
            
            headers = {
                "Authorization": f"Token {api_key}",
                "Content-Type": "audio/raw",
            }
            
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    url,
                    params=params,
                    headers=headers,
                    content=audio_data,
                    timeout=30.0
                )
                response.raise_for_status()
                result = response.json()
            
            # Extract transcript
            transcript = ""
            confidence = 1.0
            
            if result.get("results", {}).get("channels"):
                channel = result["results"]["channels"][0]
                if channel.get("alternatives"):
                    alt = channel["alternatives"][0]
                    transcript = alt.get("transcript", "")
                    confidence = alt.get("confidence", 1.0)
            
            return TranscriptResult(
                text=transcript,
                is_final=True,
                confidence=confidence
            )
            
        except Exception as e:
            logger.error(f"Deepgram transcription error: {e}")
            return TranscriptResult(text="", is_final=True, confidence=0.0)
    
    async def _transcribe_openai_whisper(
        self,
        audio_data: bytes
    ) -> TranscriptResult:
        """Transcribe using OpenAI Whisper API."""
        try:
            from openai import AsyncOpenAI
            import tempfile
            import os
            
            client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
            
            # Write to temp file (OpenAI API requires file)
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                # Add WAV header if needed
                f.write(audio_data)
                temp_path = f.name
            
            try:
                with open(temp_path, "rb") as audio_file:
                    response = await client.audio.transcriptions.create(
                        model="whisper-1",
                        file=audio_file,
                        language=self.config.language[:2]  # en-US -> en
                    )
                
                return TranscriptResult(
                    text=response.text,
                    is_final=True,
                    confidence=1.0
                )
            finally:
                os.unlink(temp_path)
                
        except Exception as e:
            logger.error(f"OpenAI Whisper error: {e}")
            return TranscriptResult(text="", is_final=True, confidence=0.0)
    
    async def _transcribe_whisper(
        self,
        audio_data: bytes
    ) -> TranscriptResult:
        """Transcribe using local Whisper model."""
        try:
            import whisper
            import numpy as np
            import tempfile
            import os
            
            # Load model if needed
            if self._whisper_model is None:
                self._whisper_model = whisper.load_model(self.config.whisper_model_size)
            
            # Save audio to temp file
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                f.write(audio_data)
                temp_path = f.name
            
            try:
                result = self._whisper_model.transcribe(
                    temp_path,
                    language=self.config.language[:2]
                )
                
                return TranscriptResult(
                    text=result["text"].strip(),
                    is_final=True,
                    confidence=1.0
                )
            finally:
                os.unlink(temp_path)
                
        except ImportError:
            logger.warning("Whisper not installed, falling back to OpenAI")
            return await self._transcribe_openai_whisper(audio_data)
        except Exception as e:
            logger.error(f"Local Whisper error: {e}")
            return TranscriptResult(text="", is_final=True, confidence=0.0)
    
    async def _stream_deepgram(
        self,
        audio_stream: AsyncIterator[bytes],
        on_transcript: Callable[[TranscriptResult], Any]
    ) -> None:
        """Stream transcription using Deepgram WebSocket."""
        try:
            import websockets
            
            api_key = self.config.deepgram_api_key
            if not api_key:
                raise ValueError("Deepgram API key not configured")
            
            url = f"wss://api.deepgram.com/v1/listen"
            params = (
                f"?model={self.config.model}"
                f"&language={self.config.language}"
                f"&punctuate={str(self.config.enable_punctuation).lower()}"
                f"&interim_results={str(self.config.enable_interim_results).lower()}"
                f"&endpointing={self.config.endpointing_ms}"
            )
            
            headers = {"Authorization": f"Token {api_key}"}
            
            async with websockets.connect(url + params, extra_headers=headers) as ws:
                # Send audio in background
                async def send_audio():
                    async for chunk in audio_stream:
                        await ws.send(chunk)
                    await ws.send(json.dumps({"type": "CloseStream"}))
                
                send_task = asyncio.create_task(send_audio())
                
                # Receive transcripts
                try:
                    async for message in ws:
                        data = json.loads(message)
                        
                        if data.get("type") == "Results":
                            channel = data.get("channel", {})
                            alternatives = channel.get("alternatives", [])
                            
                            if alternatives:
                                alt = alternatives[0]
                                result = TranscriptResult(
                                    text=alt.get("transcript", ""),
                                    is_final=data.get("is_final", False),
                                    confidence=alt.get("confidence", 1.0),
                                    start_time=data.get("start", 0.0),
                                    end_time=data.get("start", 0.0) + data.get("duration", 0.0)
                                )
                                await on_transcript(result)
                finally:
                    send_task.cancel()
                    
        except Exception as e:
            logger.error(f"Deepgram streaming error: {e}")
    
    async def _stream_buffered(
        self,
        audio_stream: AsyncIterator[bytes],
        on_transcript: Callable[[TranscriptResult], Any]
    ) -> None:
        """Buffer audio and transcribe periodically."""
        buffer = bytearray()
        buffer_duration_ms = 0
        chunk_duration_ms = 100  # Assume 100ms per chunk
        transcribe_interval_ms = 1000  # Transcribe every 1 second
        
        async for chunk in audio_stream:
            buffer.extend(chunk)
            buffer_duration_ms += chunk_duration_ms
            
            if buffer_duration_ms >= transcribe_interval_ms:
                result = await self.transcribe_audio(bytes(buffer))
                result.is_final = False  # Mark as interim
                await on_transcript(result)
                buffer.clear()
                buffer_duration_ms = 0
        
        # Final transcription
        if buffer:
            result = await self.transcribe_audio(bytes(buffer))
            result.is_final = True
            await on_transcript(result)


# Singleton instance
stt_service = STTService()
