#!/usr/bin/env python3
"""
WhisperX API Server
A FastAPI-based transcription service using WhisperX for word-level timestamps and speaker diarization.
Enhanced with chunking support for large files and video processing.
"""

import os
import gc
import torch
import whisperx
import uvicorn
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import JSONResponse
from typing import Optional
from pathlib import Path
import logging
import time

# Import our custom modules
from ffmpeg_processor import FFmpegProcessor
from video_segmenter import VideoSegmenter, AudioSegment

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="WhisperX Transcription API",
    description="Audio transcription with word-level timestamps and speaker diarization",
    version="1.0.0"
)

# Configuration
UPLOAD_DIR = Path("/app/uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

# GPU configuration
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
COMPUTE_TYPE = os.getenv("COMPUTE_TYPE", "float16" if DEVICE == "cuda" else "int8")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "16"))

# Initialize processors
ffmpeg_processor = FFmpegProcessor(use_hw_accel=True, enhance_speech=True)
video_segmenter = VideoSegmenter(chunk_duration=30, overlap_duration=10)

# Shared directory for file processing
SHARED_DIR = Path("/app/shared")
TEMP_DIR = SHARED_DIR / "temp"
TEMP_DIR.mkdir(parents=True, exist_ok=True)

logger.info(f"Starting WhisperX API Server on {DEVICE} with compute type {COMPUTE_TYPE}")


@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": "WhisperX Transcription API",
        "version": "1.0.0",
        "device": DEVICE,
        "compute_type": COMPUTE_TYPE,
        "status": "ready"
    }


@app.get("/health")
async def health_check():
    """Health check endpoint for Docker"""
    return {
        "status": "healthy",
        "device": DEVICE,
        "gpu_available": torch.cuda.is_available()
    }


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    model: str = Form(default="large-v3"),
    language: Optional[str] = Form(default=None),
    enable_diarization: bool = Form(default=True),
    min_speakers: Optional[int] = Form(default=None),
    max_speakers: Optional[int] = Form(default=None),
    hf_token: Optional[str] = Form(default=None)
):
    """
    Transcribe audio file with word-level timestamps and optional speaker diarization.

    Parameters:
    - file: Audio file (mp3, wav, m4a, etc.)
    - model: Whisper model size (tiny, base, small, medium, large-v2, large-v3, large-v3-turbo)
    - language: Language code (auto-detect if None)
    - enable_diarization: Enable speaker diarization (requires hf_token)
    - min_speakers: Minimum number of speakers (for diarization)
    - max_speakers: Maximum number of speakers (for diarization)
    - hf_token: HuggingFace token for diarization models

    Returns:
    - JSON with segments, word-level timestamps, and speaker labels
    """

    temp_file = None

    try:
        # Save uploaded file
        temp_file = UPLOAD_DIR / file.filename
        logger.info(f"Processing file: {file.filename}")

        with open(temp_file, "wb") as f:
            content = await file.read()
            f.write(content)

        # Load model
        logger.info(f"Loading Whisper model: {model}")
        model_obj = whisperx.load_model(
            model,
            device=DEVICE,
            compute_type=COMPUTE_TYPE,
            language=language
        )

        # Transcribe with whisperx
        logger.info("Starting transcription...")
        audio = whisperx.load_audio(str(temp_file))
        result = model_obj.transcribe(
            audio,
            batch_size=BATCH_SIZE
        )

        # Cleanup model to free VRAM
        del model_obj
        gc.collect()
        torch.cuda.empty_cache()

        # Align whisper output for word-level timestamps
        logger.info("Aligning timestamps...")
        detected_language = result.get("language", language)

        try:
            model_a, metadata = whisperx.load_align_model(
                language_code=detected_language,
                device=DEVICE
            )
            result = whisperx.align(
                result["segments"],
                model_a,
                metadata,
                audio,
                DEVICE,
                return_char_alignments=False
            )

            # Cleanup alignment model
            del model_a
            gc.collect()
            torch.cuda.empty_cache()

        except Exception as e:
            logger.warning(f"Alignment failed: {e}. Continuing without word-level timestamps.")

        # Speaker diarization (optional)
        if enable_diarization:
            if not hf_token:
                hf_token = os.getenv("HF_TOKEN")

            if hf_token:
                logger.info("Running speaker diarization...")
                try:
                    diarize_model = whisperx.DiarizationPipeline(
                        use_auth_token=hf_token,
                        device=DEVICE
                    )

                    diarize_segments = diarize_model(
                        audio,
                        min_speakers=min_speakers,
                        max_speakers=max_speakers
                    )

                    result = whisperx.assign_word_speakers(diarize_segments, result)

                    # Cleanup diarization model
                    del diarize_model
                    gc.collect()
                    torch.cuda.empty_cache()

                except Exception as e:
                    logger.warning(f"Diarization failed: {e}. Continuing without speaker labels.")
            else:
                logger.warning("Diarization requested but no HF_TOKEN provided. Skipping diarization.")

        # Prepare response
        response = {
            "filename": file.filename,
            "language": detected_language,
            "segments": result.get("segments", []),
            "word_segments": result.get("word_segments", [])
        }

        logger.info(f"Transcription completed for {file.filename}")
        return JSONResponse(content=response)

    except Exception as e:
        logger.error(f"Transcription error: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

    finally:
        # Cleanup temp file
        if temp_file and temp_file.exists():
            temp_file.unlink()

        # Final cleanup
        gc.collect()
        torch.cuda.empty_cache()


def transcribe_audio_segment(
    audio_path: str,
    segment: AudioSegment,
    model_name: str,
    language: Optional[str] = None
) -> dict:
    """
    Transcribe a single audio segment.

    Args:
        audio_path: Path to full audio file
        segment: AudioSegment object with start/end times
        model_name: Whisper model to use
        language: Optional language code

    Returns:
        Dictionary with transcription results
    """
    try:
        # Load full audio
        audio = whisperx.load_audio(audio_path)

        # Extract segment
        sample_rate = 16000
        start_sample = int(segment.start * sample_rate)
        end_sample = int(segment.end * sample_rate)
        segment_audio = audio[start_sample:end_sample]

        # Load model
        model = whisperx.load_model(
            model_name,
            device=DEVICE,
            compute_type=COMPUTE_TYPE,
            language=language
        )

        # Transcribe
        result = model.transcribe(segment_audio, batch_size=BATCH_SIZE)

        # Adjust timestamps to absolute time
        for seg in result.get("segments", []):
            seg["start"] += segment.start
            seg["end"] += segment.start

        # Cleanup
        del model
        gc.collect()
        torch.cuda.empty_cache()

        return {
            "segment_id": segment.segment_id,
            "start": segment.start,
            "end": segment.end,
            "segments": result.get("segments", []),
            "language": result.get("language", language)
        }

    except Exception as e:
        logger.error(f"Error transcribing segment {segment.segment_id}: {e}")
        return {
            "segment_id": segment.segment_id,
            "start": segment.start,
            "end": segment.end,
            "error": str(e),
            "segments": []
        }


@app.post("/transcribe-large")
async def transcribe_large(
    file: UploadFile = File(...),
    model: str = Form(default="large-v3"),
    language: Optional[str] = Form(default=None),
    chunking_strategy: str = Form(default="auto"),
    enable_diarization: bool = Form(default=True),
    hf_token: Optional[str] = Form(default=None)
):
    """
    Transcribe large audio/video files with automatic chunking.

    Uses VAD-based chunking for optimal performance (12x speedup per research).
    Automatically segments files >10 minutes for efficient processing.

    Parameters:
    - file: Audio or video file
    - model: Whisper model (default: large-v3)
    - language: Language code (auto-detect if None)
    - chunking_strategy: 'auto', 'vad', 'time', or 'silence'
    - enable_diarization: Enable speaker diarization
    - hf_token: HuggingFace token for diarization

    Returns:
    - JSON with stitched transcription, timestamps, and speakers
    """
    temp_file = None
    audio_file = None

    try:
        start_time = time.time()

        # Save uploaded file
        temp_file = TEMP_DIR / f"{time.time()}_{file.filename}"
        logger.info(f"Processing large file: {file.filename}")

        with open(temp_file, "wb") as f:
            content = await file.read()
            f.write(content)

        # Extract audio if video file
        if temp_file.suffix.lower() in ['.mp4', '.avi', '.mkv', '.mov', '.webm']:
            logger.info("Detected video file, extracting audio...")
            audio_file = TEMP_DIR / f"{temp_file.stem}.wav"
            ffmpeg_processor.extract_audio_optimized(str(temp_file), str(audio_file))
        else:
            audio_file = temp_file

        # Get audio duration
        info = ffmpeg_processor.get_video_info(str(audio_file))
        duration = info.get('duration', 0)
        logger.info(f"Audio duration: {duration:.1f}s")

        # Segment audio
        segments = video_segmenter.segment_audio(str(audio_file), strategy=chunking_strategy)
        logger.info(f"Created {len(segments)} segments using '{chunking_strategy}' strategy")

        # Transcribe segments sequentially (to manage VRAM)
        all_segments = []
        detected_language = language

        for i, seg in enumerate(segments):
            logger.info(f"Transcribing segment {i+1}/{len(segments)} ({seg.start:.1f}s - {seg.end:.1f}s)")
            result = transcribe_audio_segment(str(audio_file), seg, model, language)

            if not detected_language and result.get('language'):
                detected_language = result['language']

            all_segments.extend(result.get('segments', []))

        # Align for word-level timestamps
        logger.info("Aligning timestamps across all segments...")
        audio = whisperx.load_audio(str(audio_file))

        try:
            model_a, metadata = whisperx.load_align_model(
                language_code=detected_language or 'en',
                device=DEVICE
            )
            result = whisperx.align(
                all_segments,
                model_a,
                metadata,
                audio,
                DEVICE,
                return_char_alignments=False
            )
            all_segments = result.get("segments", all_segments)

            del model_a
            gc.collect()
            torch.cuda.empty_cache()

        except Exception as e:
            logger.warning(f"Alignment failed: {e}")

        # Diarization (optional)
        if enable_diarization:
            if not hf_token:
                hf_token = os.getenv("HF_TOKEN")

            if hf_token:
                logger.info("Running speaker diarization...")
                try:
                    diarize_model = whisperx.DiarizationPipeline(
                        use_auth_token=hf_token,
                        device=DEVICE
                    )
                    diarize_segments = diarize_model(audio)
                    all_segments = whisperx.assign_word_speakers(diarize_segments, {"segments": all_segments})["segments"]

                    del diarize_model
                    gc.collect()
                    torch.cuda.empty_cache()

                except Exception as e:
                    logger.warning(f"Diarization failed: {e}")

        processing_time = time.time() - start_time
        realtime_factor = duration / processing_time if processing_time > 0 else 0

        response = {
            "filename": file.filename,
            "duration": duration,
            "language": detected_language,
            "num_segments": len(all_segments),
            "num_chunks": len(segments),
            "chunking_strategy": chunking_strategy,
            "processing_time": processing_time,
            "realtime_factor": realtime_factor,
            "segments": all_segments
        }

        logger.info(f"Large file transcription completed in {processing_time:.1f}s ({realtime_factor:.1f}x realtime)")
        return JSONResponse(content=response)

    except Exception as e:
        logger.error(f"Large file transcription error: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

    finally:
        # Cleanup temp files
        if temp_file and temp_file.exists():
            temp_file.unlink()
        if audio_file and audio_file != temp_file and audio_file.exists():
            audio_file.unlink()

        gc.collect()
        torch.cuda.empty_cache()


@app.post("/process-video")
async def process_video(
    file: UploadFile = File(...),
    model: str = Form(default="large-v3"),
    language: Optional[str] = Form(default=None),
    enhance_audio: bool = Form(default=True),
    enable_diarization: bool = Form(default=True),
    hf_token: Optional[str] = Form(default=None)
):
    """
    Process video file: extract audio, enhance, and transcribe.

    Optimized workflow for video transcription with speech enhancement.

    Parameters:
    - file: Video file (mp4, avi, mkv, etc.)
    - model: Whisper model
    - language: Language code
    - enhance_audio: Apply speech enhancement filters
    - enable_diarization: Enable speaker diarization
    - hf_token: HuggingFace token

    Returns:
    - JSON with video metadata and transcription
    """
    temp_video = None
    temp_audio = None

    try:
        # Save video
        temp_video = TEMP_DIR / f"{time.time()}_{file.filename}"
        logger.info(f"Processing video: {file.filename}")

        with open(temp_video, "wb") as f:
            content = await file.read()
            f.write(content)

        # Get video info
        video_info = ffmpeg_processor.get_video_info(str(temp_video))

        # Extract and enhance audio
        temp_audio = TEMP_DIR / f"{temp_video.stem}.wav"

        if enhance_audio:
            logger.info("Extracting and enhancing audio...")
            ffmpeg_processor.extract_audio_optimized(str(temp_video), str(temp_audio))
        else:
            # Basic extraction without enhancement
            ffmpeg_processor.extract_audio_optimized(
                str(temp_video),
                str(temp_audio),
                sample_rate=16000,
                channels=1
            )

        # Use the large file endpoint for transcription
        # (This reuses the chunking logic)
        logger.info("Transcribing extracted audio...")

        # Create a mock UploadFile for internal processing
        with open(temp_audio, "rb") as audio_file:
            audio_content = audio_file.read()

            # Process through large file transcription
            class MockUploadFile:
                def __init__(self, filename, content):
                    self.filename = filename
                    self._content = content

                async def read(self):
                    return self._content

            mock_file = MockUploadFile(temp_audio.name, audio_content)

            # Transcribe using large file endpoint logic
            transcription_result = await transcribe_large(
                file=mock_file,
                model=model,
                language=language,
                chunking_strategy="auto",
                enable_diarization=enable_diarization,
                hf_token=hf_token
            )

            # Add video metadata to response
            result_data = transcription_result.body.decode('utf-8')
            import json
            transcription_data = json.loads(result_data)

            transcription_data["video_info"] = {
                "format": video_info.get("format", ""),
                "duration": video_info.get("duration", 0),
                "size_bytes": video_info.get("size_bytes", 0),
                "video_codec": video_info.get("video_codec", ""),
                "resolution": f"{video_info.get('video_width', 0)}x{video_info.get('video_height', 0)}",
                "audio_codec": video_info.get("audio_codec", "")
            }

            return JSONResponse(content=transcription_data)

    except Exception as e:
        logger.error(f"Video processing error: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Video processing failed: {str(e)}")

    finally:
        # Cleanup
        if temp_video and temp_video.exists():
            temp_video.unlink()
        if temp_audio and temp_audio.exists():
            temp_audio.unlink()

        gc.collect()
        torch.cuda.empty_cache()


@app.get("/models")
async def list_models():
    """List available Whisper models"""
    return {
        "models": [
            "tiny",
            "base",
            "small",
            "medium",
            "large-v2",
            "large-v3",
            "large-v3-turbo"
        ],
        "recommended_for_rtx3090": ["large-v3", "large-v3-turbo"],
        "note": "large-v3 provides best accuracy, large-v3-turbo is 6x faster with similar quality"
    }


if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info"
    )
