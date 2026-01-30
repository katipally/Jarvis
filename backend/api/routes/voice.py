"""
Jarvis Voice API Routes

REST and WebSocket endpoints for voice interactions:
- TTS synthesis
- STT transcription
- Voice configuration
- Voice WebSocket for real-time conversation
"""

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect, UploadFile, File
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Optional, List
import json
import asyncio
import base64

from services.voice import (
    VoiceConfig, voice_config,
    tts_service, stt_service, vad_service,
    voice_pipeline
)
from core.logger import setup_logger

router = APIRouter()
logger = setup_logger(__name__)


# ============== Request Models ==============

class TTSSynthesizeRequest(BaseModel):
    """Request for TTS synthesis."""
    text: str = Field(..., description="Text to synthesize")
    voice: Optional[str] = Field(None, description="Voice ID")
    speed: Optional[float] = Field(1.0, description="Speech speed", ge=0.5, le=2.0)
    format: str = Field("mp3", description="Output format: mp3, wav, pcm")


class STTTranscribeRequest(BaseModel):
    """Request for STT transcription."""
    audio_data: str = Field(..., description="Base64 encoded audio")
    format: str = Field("wav", description="Audio format")
    sample_rate: int = Field(16000, description="Sample rate")


class VoiceConfigUpdateRequest(BaseModel):
    """Request to update voice configuration."""
    stt_provider: Optional[str] = None
    tts_provider: Optional[str] = None
    tts_voice: Optional[str] = None
    tts_speed: Optional[float] = None
    vad_threshold: Optional[float] = None
    enable_interruption: Optional[bool] = None


# ============== TTS Routes ==============

@router.post("/voice/tts/synthesize")
async def synthesize_speech(request: TTSSynthesizeRequest):
    """
    Synthesize text to speech.
    
    Returns audio data as base64.
    """
    try:
        chunk = await tts_service.synthesize(
            text=request.text,
            voice=request.voice,
            speed=request.speed
        )
        
        return {
            "audio_data": chunk.to_base64(),
            "format": chunk.format,
            "sample_rate": chunk.sample_rate,
            "text_length": len(request.text)
        }
        
    except Exception as e:
        logger.error(f"TTS synthesis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/voice/tts/stream")
async def stream_speech(request: TTSSynthesizeRequest):
    """
    Stream TTS synthesis sentence by sentence.
    
    Returns SSE stream of audio chunks.
    """
    async def generate():
        try:
            async for chunk in tts_service.stream_synthesis(
                text=request.text,
                voice=request.voice,
                speed=request.speed
            ):
                data = {
                    "audio_data": chunk.to_base64(),
                    "format": chunk.format,
                    "text_segment": chunk.text_segment,
                    "is_final": chunk.is_final
                }
                yield f"data: {json.dumps(data)}\n\n"
            
            yield f"data: {json.dumps({'type': 'done'})}\n\n"
            
        except Exception as e:
            logger.error(f"TTS stream error: {e}")
            yield f"data: {json.dumps({'type': 'error', 'error': str(e)})}\n\n"
    
    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache"}
    )


@router.get("/voice/tts/voices")
async def get_voices():
    """Get available TTS voices."""
    try:
        voices = await tts_service.get_available_voices()
        return {"voices": voices, "current": voice_config.tts.voice}
    except Exception as e:
        logger.error(f"Get voices error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============== STT Routes ==============

@router.post("/voice/stt/transcribe")
async def transcribe_audio(request: STTTranscribeRequest):
    """
    Transcribe audio to text.
    """
    try:
        # Decode base64 audio
        audio_data = base64.b64decode(request.audio_data)
        
        result = await stt_service.transcribe_audio(
            audio_data=audio_data,
            sample_rate=request.sample_rate
        )
        
        return {
            "text": result.text,
            "confidence": result.confidence,
            "is_final": result.is_final
        }
        
    except Exception as e:
        logger.error(f"STT transcription error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/voice/stt/upload")
async def transcribe_upload(file: UploadFile = File(...)):
    """
    Transcribe uploaded audio file.
    """
    try:
        audio_data = await file.read()
        
        result = await stt_service.transcribe_audio(
            audio_data=audio_data,
            sample_rate=16000  # Assume 16kHz
        )
        
        return {
            "text": result.text,
            "confidence": result.confidence,
            "filename": file.filename
        }
        
    except Exception as e:
        logger.error(f"STT upload error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============== Configuration Routes ==============

@router.get("/voice/config")
async def get_voice_config():
    """Get current voice configuration."""
    return {
        "config": voice_config.to_dict(),
        "stt_provider": voice_config.stt.provider,
        "tts_provider": voice_config.tts.provider,
    }


@router.post("/voice/config")
async def update_voice_config(request: VoiceConfigUpdateRequest):
    """Update voice configuration."""
    try:
        if request.stt_provider:
            voice_config.stt.provider = request.stt_provider
        
        if request.tts_provider:
            voice_config.tts.provider = request.tts_provider
        
        if request.tts_voice:
            voice_config.tts.voice = request.tts_voice
        
        if request.tts_speed is not None:
            voice_config.tts.speed = request.tts_speed
        
        if request.vad_threshold is not None:
            voice_config.vad.threshold = request.vad_threshold
        
        if request.enable_interruption is not None:
            voice_config.pipeline.enable_interruption = request.enable_interruption
        
        return {
            "status": "updated",
            "config": voice_config.to_dict()
        }
        
    except Exception as e:
        logger.error(f"Config update error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============== Pipeline Status ==============

@router.get("/voice/pipeline/status")
async def get_pipeline_status():
    """Get voice pipeline status."""
    return voice_pipeline.get_status()


# ============== WebSocket for Real-time Voice ==============

@router.websocket("/ws/voice")
async def voice_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for real-time voice interaction.
    
    Client Messages:
    - {"type": "audio", "data": "<base64>", "sample_rate": 16000}
    - {"type": "config", "config": {...}}
    - {"type": "interrupt"}
    - {"type": "ping"}
    
    Server Messages:
    - {"type": "vad", "is_speech": bool, "probability": float}
    - {"type": "transcript", "text": "...", "is_final": bool}
    - {"type": "audio", "data": "<base64>", "text_segment": "..."}
    - {"type": "state", "state": "listening|processing|speaking|idle"}
    - {"type": "error", "error": "..."}
    - {"type": "pong"}
    """
    await websocket.accept()
    
    logger.info("Voice WebSocket connected")
    
    # Initialize pipeline
    await voice_pipeline.initialize()
    
    # Register event handler
    async def event_handler(event):
        try:
            response = {"type": event.event_type}
            if isinstance(event.data, dict):
                response.update(event.data)
            else:
                response["data"] = event.data
            await websocket.send_json(response)
        except Exception as e:
            logger.error(f"WebSocket send error: {e}")
    
    voice_pipeline.on_event(event_handler)
    
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            msg_type = message.get("type", "")
            
            if msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            
            elif msg_type == "audio":
                # Process audio input
                audio_data = base64.b64decode(message.get("data", ""))
                sample_rate = message.get("sample_rate", 16000)
                
                result = await voice_pipeline.process_audio_input(
                    audio_data, sample_rate
                )
                
                if result and result.text:
                    await websocket.send_json({
                        "type": "transcript_final",
                        "text": result.text,
                        "confidence": result.confidence
                    })
            
            elif msg_type == "synthesize":
                # Synthesize and stream response
                text = message.get("text", "")
                voice = message.get("voice")
                
                async for chunk in voice_pipeline.synthesize_response(text, voice):
                    await websocket.send_json({
                        "type": "audio",
                        "data": chunk.to_base64(),
                        "text_segment": chunk.text_segment,
                        "is_final": chunk.is_final
                    })
            
            elif msg_type == "interrupt":
                await voice_pipeline.cancel_playback()
                await websocket.send_json({"type": "interrupted"})
            
            elif msg_type == "config":
                # Update configuration
                config_data = message.get("config", {})
                # Apply config updates
                await websocket.send_json({"type": "config_updated"})
            
            elif msg_type == "reset":
                voice_pipeline.reset()
                await websocket.send_json({"type": "reset_complete"})
    
    except WebSocketDisconnect:
        logger.info("Voice WebSocket disconnected")
    except Exception as e:
        logger.error(f"Voice WebSocket error: {e}")
        try:
            await websocket.send_json({"type": "error", "error": str(e)})
        except:
            pass
    finally:
        voice_pipeline.reset()
