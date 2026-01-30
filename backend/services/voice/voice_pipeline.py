"""
Jarvis Voice Pipeline

Pipecat-inspired real-time voice processing pipeline:
- Input: Audio → VAD → STT → Text
- Output: Text → LLM → TTS → Audio
- Features: Interruption handling, sentence streaming
"""

from typing import Optional, Callable, Any, AsyncIterator
from dataclasses import dataclass, field
from enum import Enum
import asyncio
from datetime import datetime

from .voice_config import VoiceConfig, voice_config
from .stt_service import STTService, TranscriptResult, stt_service
from .tts_service import TTSService, AudioChunk, tts_service
from .vad_service import VADService, VADResult, SpeechState, vad_service
from core.logger import setup_logger

logger = setup_logger(__name__)


class PipelineState(Enum):
    """Current pipeline state."""
    IDLE = "idle"
    LISTENING = "listening"
    PROCESSING = "processing"
    SPEAKING = "speaking"
    INTERRUPTED = "interrupted"


@dataclass
class PipelineEvent:
    """Event emitted by the pipeline."""
    event_type: str  # vad, transcript, audio, state_change, error
    data: Any
    timestamp: datetime = field(default_factory=datetime.now)
    
    def to_dict(self):
        return {
            "event_type": self.event_type,
            "data": self.data if isinstance(self.data, dict) else str(self.data),
            "timestamp": self.timestamp.isoformat(),
        }


class VoicePipeline:
    """
    Real-time voice processing pipeline.
    
    Features:
    - Full-duplex audio processing
    - VAD-based endpoint detection
    - Interruption handling (user speaks during TTS)
    - Sentence-by-sentence TTS streaming
    """
    
    def __init__(
        self,
        config: Optional[VoiceConfig] = None,
        stt: Optional[STTService] = None,
        tts: Optional[TTSService] = None,
        vad: Optional[VADService] = None
    ):
        self.config = config or voice_config
        self.stt = stt or stt_service
        self.tts = tts or tts_service
        self.vad = vad or vad_service
        
        # Pipeline state
        self._state = PipelineState.IDLE
        self._is_playing = False
        self._interrupted = False
        
        # Audio buffers
        self._audio_buffer = bytearray()
        
        # Event callbacks
        self._event_handlers: list[Callable[[PipelineEvent], Any]] = []
        
        # Tasks
        self._current_tts_task: Optional[asyncio.Task] = None
    
    @property
    def state(self) -> PipelineState:
        return self._state
    
    def on_event(self, handler: Callable[[PipelineEvent], Any]):
        """Register event handler."""
        self._event_handlers.append(handler)
    
    async def _emit_event(self, event_type: str, data: Any):
        """Emit event to all handlers."""
        event = PipelineEvent(event_type=event_type, data=data)
        for handler in self._event_handlers:
            try:
                result = handler(event)
                if asyncio.iscoroutine(result):
                    await result
            except Exception as e:
                logger.error(f"Event handler error: {e}")
    
    async def initialize(self):
        """Initialize pipeline components."""
        await self.vad.initialize()
        self._state = PipelineState.IDLE
        logger.info("Voice pipeline initialized")
    
    def reset(self):
        """Reset pipeline state."""
        self._state = PipelineState.IDLE
        self._is_playing = False
        self._interrupted = False
        self._audio_buffer.clear()
        self.vad.reset()
    
    async def process_audio_input(
        self,
        audio_data: bytes,
        sample_rate: int = 16000
    ) -> Optional[TranscriptResult]:
        """
        Process incoming audio through VAD and STT.
        
        Args:
            audio_data: Raw audio bytes
            sample_rate: Audio sample rate
        
        Returns:
            TranscriptResult if speech detected and transcribed
        """
        # VAD processing
        vad_result = await self.vad.process_audio(audio_data, sample_rate)
        
        await self._emit_event("vad", vad_result.to_dict())
        
        # Check for interruption during playback
        if self._is_playing and vad_result.is_speech:
            if self.config.pipeline.enable_interruption:
                probability_threshold = 0.7  # Higher threshold during playback
                if vad_result.probability >= probability_threshold:
                    await self._handle_interruption()
                    return None
        
        # Handle speech states
        if vad_result.state == SpeechState.SPEECH_START:
            self._state = PipelineState.LISTENING
            self._audio_buffer.clear()
            await self._emit_event("state_change", {"state": "listening"})
        
        if vad_result.is_speech and self._state == PipelineState.LISTENING:
            self._audio_buffer.extend(audio_data)
        
        if vad_result.state == SpeechState.SPEECH_END:
            self._state = PipelineState.PROCESSING
            await self._emit_event("state_change", {"state": "processing"})
            
            # Transcribe buffered audio
            if self._audio_buffer:
                transcript = await self.stt.transcribe_audio(
                    bytes(self._audio_buffer),
                    sample_rate
                )
                
                self._audio_buffer.clear()
                
                if transcript.text:
                    await self._emit_event("transcript", transcript.to_dict())
                    return transcript
        
        return None
    
    async def stream_audio_input(
        self,
        audio_stream: AsyncIterator[bytes],
        sample_rate: int = 16000
    ) -> AsyncIterator[TranscriptResult]:
        """
        Stream audio input and yield transcripts.
        
        Args:
            audio_stream: Async iterator of audio chunks
            sample_rate: Audio sample rate
        
        Yields:
            TranscriptResult for each detected utterance
        """
        async for audio_chunk in audio_stream:
            if self._interrupted:
                self._interrupted = False
                self.vad.reset()
                continue
            
            result = await self.process_audio_input(audio_chunk, sample_rate)
            
            if result and result.text:
                yield result
    
    async def synthesize_response(
        self,
        text: str,
        voice: Optional[str] = None
    ) -> AsyncIterator[AudioChunk]:
        """
        Synthesize text response to audio with sentence streaming.
        
        Args:
            text: Text to synthesize
            voice: Optional voice override
        
        Yields:
            AudioChunk for each sentence
        """
        self._state = PipelineState.SPEAKING
        self._is_playing = True
        
        await self._emit_event("state_change", {"state": "speaking"})
        
        try:
            async for chunk in self.tts.stream_synthesis(text, voice):
                if self._interrupted:
                    logger.info("TTS interrupted")
                    break
                
                await self._emit_event("audio", chunk.to_dict())
                yield chunk
                
                # Small delay between sentences for natural pacing
                if not chunk.is_final:
                    await asyncio.sleep(0.05)
        finally:
            self._is_playing = False
            
            if not self._interrupted:
                self._state = PipelineState.IDLE
                await self._emit_event("state_change", {"state": "idle"})
    
    async def _handle_interruption(self):
        """Handle user interruption during TTS playback."""
        logger.info("Interruption detected")
        
        self._interrupted = True
        self._is_playing = False
        self._state = PipelineState.INTERRUPTED
        
        # Cancel current TTS task if running
        if self._current_tts_task and not self._current_tts_task.done():
            self._current_tts_task.cancel()
        
        await self._emit_event("state_change", {"state": "interrupted"})
        await self._emit_event("interruption", {"reason": "user_speech"})
        
        # Reset to listening state
        self.vad.reset()
        self._audio_buffer.clear()
        self._state = PipelineState.LISTENING
    
    async def cancel_playback(self):
        """Cancel current audio playback."""
        if self._is_playing:
            self._interrupted = True
            await self._emit_event("playback_cancelled", {})
    
    def get_status(self) -> dict:
        """Get current pipeline status."""
        return {
            "state": self._state.value,
            "is_playing": self._is_playing,
            "is_interrupted": self._interrupted,
            "vad_state": self.vad._current_state.value,
            "config": self.config.to_dict()
        }


# Singleton instance
voice_pipeline = VoicePipeline()
