"""
Voice Pipeline Configuration

Centralized configuration for all voice components.
"""

from dataclasses import dataclass, field
from typing import Optional, Literal, Dict, Any
import os


@dataclass
class STTConfig:
    """Speech-to-text configuration."""
    provider: Literal["deepgram", "whisper", "apple"] = "deepgram"
    model: str = "nova-2"
    language: str = "en-US"
    
    # Deepgram specific
    deepgram_api_key: Optional[str] = field(default_factory=lambda: os.getenv("DEEPGRAM_API_KEY"))
    
    # Whisper specific
    whisper_model_size: str = "base"  # tiny, base, small, medium, large
    
    # Streaming options
    enable_streaming: bool = True
    enable_interim_results: bool = True
    enable_punctuation: bool = True
    enable_profanity_filter: bool = False
    
    # Timing
    endpointing_ms: int = 500  # Silence duration to end utterance


@dataclass
class TTSConfig:
    """Text-to-speech configuration."""
    provider: Literal["chatterbox", "elevenlabs", "openai", "apple"] = "openai"
    model: str = "tts-1"
    voice: str = "alloy"  # OpenAI: alloy, echo, fable, onyx, nova, shimmer
    
    # API keys
    elevenlabs_api_key: Optional[str] = field(default_factory=lambda: os.getenv("ELEVENLABS_API_KEY"))
    chatterbox_api_key: Optional[str] = field(default_factory=lambda: os.getenv("CHATTERBOX_API_KEY"))
    
    # Voice parameters
    speed: float = 1.0
    pitch: float = 1.0
    
    # Chatterbox specific
    emotion_level: float = 0.5  # 0=monotone, 1=expressive
    
    # Output format
    output_format: str = "mp3"  # mp3, pcm, wav
    sample_rate: int = 24000


@dataclass
class VADConfig:
    """Voice activity detection configuration."""
    provider: Literal["silero", "webrtc", "energy"] = "silero"
    
    # Detection thresholds
    threshold: float = 0.5  # Speech probability threshold
    
    # Timing (in milliseconds)
    min_speech_duration_ms: int = 250  # Minimum speech duration
    min_silence_duration_ms: int = 500  # Silence to end speech
    padding_ms: int = 100  # Padding around speech
    
    # Model
    silero_model_path: Optional[str] = None
    
    # Audio parameters
    sample_rate: int = 16000
    chunk_size_ms: int = 30  # Process in 30ms chunks


@dataclass
class PipelineConfig:
    """Overall pipeline configuration."""
    # Interruption handling
    enable_interruption: bool = True
    interruption_threshold: float = 0.6  # VAD threshold during TTS playback
    
    # Sentence boundary streaming
    enable_sentence_streaming: bool = True
    
    # Audio buffer
    input_buffer_size: int = 4096
    output_buffer_size: int = 4096
    
    # Latency targets
    max_stt_latency_ms: int = 200
    max_tts_latency_ms: int = 300
    
    # Noise suppression
    enable_noise_suppression: bool = True
    noise_suppression_level: int = 2  # 0-4


@dataclass
class VoiceConfig:
    """Complete voice configuration."""
    stt: STTConfig = field(default_factory=STTConfig)
    tts: TTSConfig = field(default_factory=TTSConfig)
    vad: VADConfig = field(default_factory=VADConfig)
    pipeline: PipelineConfig = field(default_factory=PipelineConfig)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "stt": {
                "provider": self.stt.provider,
                "model": self.stt.model,
                "language": self.stt.language,
                "enable_streaming": self.stt.enable_streaming,
            },
            "tts": {
                "provider": self.tts.provider,
                "model": self.tts.model,
                "voice": self.tts.voice,
                "speed": self.tts.speed,
            },
            "vad": {
                "provider": self.vad.provider,
                "threshold": self.vad.threshold,
                "min_speech_duration_ms": self.vad.min_speech_duration_ms,
            },
            "pipeline": {
                "enable_interruption": self.pipeline.enable_interruption,
                "enable_sentence_streaming": self.pipeline.enable_sentence_streaming,
            }
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "VoiceConfig":
        """Create from dictionary."""
        config = cls()
        
        if "stt" in data:
            for k, v in data["stt"].items():
                if hasattr(config.stt, k):
                    setattr(config.stt, k, v)
        
        if "tts" in data:
            for k, v in data["tts"].items():
                if hasattr(config.tts, k):
                    setattr(config.tts, k, v)
        
        if "vad" in data:
            for k, v in data["vad"].items():
                if hasattr(config.vad, k):
                    setattr(config.vad, k, v)
        
        if "pipeline" in data:
            for k, v in data["pipeline"].items():
                if hasattr(config.pipeline, k):
                    setattr(config.pipeline, k, v)
        
        return config


# Global configuration instance
voice_config = VoiceConfig()
