"""
Voice Activity Detection (VAD) Service

Detects speech in audio stream for:
- Endpoint detection (when user stops speaking)
- Interruption handling (user speaks during TTS)
- Noise filtering
"""

from typing import Optional, Callable, Any, List
from dataclasses import dataclass, field
from enum import Enum
import asyncio
import numpy as np

from .voice_config import VADConfig
from core.logger import setup_logger

logger = setup_logger(__name__)


class SpeechState(Enum):
    """Current speech detection state."""
    SILENCE = "silence"
    SPEECH_START = "speech_start"
    SPEECH = "speech"
    SPEECH_END = "speech_end"


@dataclass
class VADResult:
    """Result from VAD processing."""
    is_speech: bool
    probability: float
    state: SpeechState
    duration_ms: float = 0.0
    
    def to_dict(self):
        return {
            "is_speech": self.is_speech,
            "probability": self.probability,
            "state": self.state.value,
            "duration_ms": self.duration_ms,
        }


class VADService:
    """
    Voice Activity Detection service.
    
    Uses Silero VAD for accurate speech detection.
    Falls back to energy-based detection if Silero unavailable.
    """
    
    def __init__(self, config: Optional[VADConfig] = None):
        self.config = config or VADConfig()
        self._silero_model = None
        self._silero_utils = None
        
        # State tracking
        self._speech_frames = 0
        self._silence_frames = 0
        self._current_state = SpeechState.SILENCE
        self._speech_start_time = 0.0
        
        # Frame timing
        self._frame_duration_ms = self.config.chunk_size_ms
    
    async def initialize(self):
        """Initialize VAD model."""
        if self.config.provider == "silero":
            await self._init_silero()
    
    async def _init_silero(self):
        """Initialize Silero VAD model."""
        try:
            import torch
            
            # Load Silero VAD model
            model, utils = torch.hub.load(
                repo_or_dir='snakers4/silero-vad',
                model='silero_vad',
                force_reload=False,
                trust_repo=True
            )
            
            self._silero_model = model
            self._silero_utils = utils
            logger.info("Silero VAD model loaded successfully")
            
        except Exception as e:
            logger.warning(f"Failed to load Silero VAD: {e}. Using energy-based detection.")
            self.config.provider = "energy"
    
    def reset(self):
        """Reset VAD state."""
        self._speech_frames = 0
        self._silence_frames = 0
        self._current_state = SpeechState.SILENCE
        self._speech_start_time = 0.0
    
    async def process_audio(
        self,
        audio_data: bytes,
        sample_rate: int = 16000
    ) -> VADResult:
        """
        Process audio chunk and detect speech.
        
        Args:
            audio_data: Raw audio bytes (16-bit PCM)
            sample_rate: Audio sample rate
        
        Returns:
            VADResult with speech detection info
        """
        provider = self.config.provider
        
        if provider == "silero" and self._silero_model is not None:
            probability = await self._detect_silero(audio_data, sample_rate)
        else:
            probability = self._detect_energy(audio_data)
        
        is_speech = probability >= self.config.threshold
        
        # Update state machine
        new_state = self._update_state(is_speech)
        
        # Calculate speech duration
        duration_ms = 0.0
        if new_state == SpeechState.SPEECH_END:
            duration_ms = self._speech_frames * self._frame_duration_ms
        
        return VADResult(
            is_speech=is_speech,
            probability=probability,
            state=new_state,
            duration_ms=duration_ms
        )
    
    def _update_state(self, is_speech: bool) -> SpeechState:
        """Update VAD state machine."""
        min_speech_frames = self.config.min_speech_duration_ms // self._frame_duration_ms
        min_silence_frames = self.config.min_silence_duration_ms // self._frame_duration_ms
        
        if is_speech:
            self._speech_frames += 1
            self._silence_frames = 0
            
            if self._current_state == SpeechState.SILENCE:
                if self._speech_frames >= min_speech_frames:
                    self._current_state = SpeechState.SPEECH_START
                    return SpeechState.SPEECH_START
            elif self._current_state == SpeechState.SPEECH_START:
                self._current_state = SpeechState.SPEECH
                return SpeechState.SPEECH
            
            return SpeechState.SPEECH if self._current_state != SpeechState.SILENCE else SpeechState.SILENCE
        
        else:
            self._silence_frames += 1
            
            if self._current_state in [SpeechState.SPEECH_START, SpeechState.SPEECH]:
                if self._silence_frames >= min_silence_frames:
                    old_speech_frames = self._speech_frames
                    self._speech_frames = 0
                    self._current_state = SpeechState.SPEECH_END
                    return SpeechState.SPEECH_END
                return SpeechState.SPEECH
            
            self._speech_frames = 0
            self._current_state = SpeechState.SILENCE
            return SpeechState.SILENCE
    
    async def _detect_silero(
        self,
        audio_data: bytes,
        sample_rate: int
    ) -> float:
        """Detect speech using Silero VAD."""
        try:
            import torch
            
            # Convert bytes to numpy array
            audio_np = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
            
            # Resample if needed (Silero expects 16kHz)
            if sample_rate != 16000:
                # Simple resampling
                ratio = 16000 / sample_rate
                new_length = int(len(audio_np) * ratio)
                indices = np.linspace(0, len(audio_np) - 1, new_length).astype(int)
                audio_np = audio_np[indices]
            
            # Convert to tensor
            audio_tensor = torch.from_numpy(audio_np)
            
            # Get speech probability
            with torch.no_grad():
                probability = self._silero_model(audio_tensor, 16000).item()
            
            return probability
            
        except Exception as e:
            logger.error(f"Silero VAD error: {e}")
            return self._detect_energy(audio_data)
    
    def _detect_energy(self, audio_data: bytes) -> float:
        """
        Simple energy-based speech detection.
        Fallback when Silero is unavailable.
        """
        try:
            # Convert to numpy
            audio_np = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32)
            
            # Calculate RMS energy
            rms = np.sqrt(np.mean(audio_np ** 2))
            
            # Normalize to 0-1 range (assume max is 10000)
            probability = min(rms / 10000.0, 1.0)
            
            return probability
            
        except Exception as e:
            logger.error(f"Energy VAD error: {e}")
            return 0.0
    
    async def detect_interruption(
        self,
        audio_data: bytes,
        is_playing_audio: bool,
        sample_rate: int = 16000
    ) -> bool:
        """
        Detect if user is interrupting during audio playback.
        
        Uses a higher threshold during playback to avoid false positives
        from speaker feedback.
        """
        if not is_playing_audio:
            return False
        
        result = await self.process_audio(audio_data, sample_rate)
        
        # Use higher threshold for interruption
        interruption_threshold = self.config.threshold + 0.1
        
        return result.probability >= interruption_threshold


# Singleton instance
vad_service = VADService()
