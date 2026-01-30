"""
Jarvis Voice Pipeline

Pipecat-inspired real-time voice architecture:
- STT: Speech-to-text (Deepgram, Whisper, Apple)
- TTS: Text-to-speech (Chatterbox, ElevenLabs, Apple)
- VAD: Voice activity detection (Silero)
- Pipeline: Audio processing and streaming
"""

from .voice_config import VoiceConfig, voice_config
from .stt_service import STTService, stt_service
from .tts_service import TTSService, tts_service
from .vad_service import VADService, vad_service
from .voice_pipeline import VoicePipeline, voice_pipeline

__all__ = [
    "VoiceConfig",
    "voice_config",
    "STTService",
    "stt_service",
    "TTSService",
    "tts_service",
    "VADService",
    "vad_service",
    "VoicePipeline",
    "voice_pipeline",
]
