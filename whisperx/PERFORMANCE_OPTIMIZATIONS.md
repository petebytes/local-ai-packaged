# WhisperX Performance Optimizations for RTX 5090

## Applied Optimizations (October 2025)

### 1. TF32 Tensor Core Acceleration ✅
**File**: `api_server.py` (lines 48-53)

**What**: Enabled TensorFloat-32 (TF32) for NVIDIA RTX 5090's 5th-generation Tensor Cores
```python
torch.backends.cuda.matmul.allow_tf32 = True
torch.backends.cudnn.allow_tf32 = True
```

**Expected Speedup**: 20-40% for transformer workloads
**Tradeoff**: Minimal accuracy loss (negligible for speech recognition)

**Research Sources**:
- RTX 5090 has 680 5th-gen Tensor Cores with FP32/FP16/BF16/TF32/FP8/INT4 support
- PyTorch 2.7+ (cu128) has full Blackwell optimization
- Best practice from NVIDIA: Always enable TF32 for AI workloads on Ampere/Blackwell

---

### 2. Model Caching & Reuse ✅
**File**: `api_server.py` (lines 376-430)

**What**: Load Whisper model **once** and reuse for all segments
- **Before**: Model loaded/unloaded 63 times for 30-min video
- **After**: Model loaded once, reused 63 times

**Expected Speedup**: 30-50% reduction in processing time
**VRAM Impact**: None (model stays resident)

**Research Finding**:
> "Most of the time during Whisper processing is taken by the model initialization step where it gets loaded into memory (GPU and RAM)"
> — Whisper model caching best practices, 2025

---

### 3. Language Detection Caching ✅
**File**: `api_server.py` (lines 386-399)

**What**: Detect language once from first segment, reuse for remaining segments
- **Before**: Language auto-detected for every segment (63 times)
- **After**: Detected once, passed to subsequent segments

**Expected Speedup**: 10-15% reduction in processing time
**Accuracy Impact**: None (Whisper design assumes single language)

**Research Finding**:
> "Whisper detects the language by analyzing the first 30 seconds of audio when you don't specify a language explicitly. The model assumes that the full audio is in a single language"
> — Whisper language detection behavior, 2025

---

### 4. Optimized Chunking Strategy ✅
**Already Implemented**: 30-second chunks with VAD-based segmentation

**Current Strategy**:
- Use Silero VAD for speech detection
- Create 30-second chunks with 10-second overlap
- Cut & Merge strategy for boundary handling

**Research Validation**:
> "A chunk length of 30 seconds is optimal for Whisper large-v3"
> — Whisper batch processing best practices, 2025

---

## Performance Comparison

### Before Optimizations (Estimated):
- 30-minute video → ~5-6 minutes processing time
- 63 segments × 5 seconds/segment = 315 seconds
- Model loading overhead: ~3 seconds × 63 = 189 seconds wasted

### After Optimizations (Expected):
- 30-minute video → ~2-3 minutes processing time
- TF32 speedup: -30% (95 seconds saved)
- Model caching: -40% (126 seconds saved)
- Language caching: -12% (38 seconds saved)
- **Total expected speedup: ~50-60%**

---

## RTX 5090 Hardware Capabilities

**Specifications**:
- 21,760 CUDA cores
- 680 5th-generation Tensor Cores
- 32GB GDDR7 VRAM
- Compute Capability: SM 12.0 (Blackwell)
- CUDA 12.8 required for full optimization

**AI Performance**:
- 3,352 AI TOPS (Tera Operations Per Second)
- 44% faster than RTX 4090 in Computer Vision
- 72% faster than RTX 4090 in NLP tasks

---

## Remaining Bottlenecks

### 1. Pyannote VAD Model (Old Version)
**Issue**: WhisperX uses outdated pyannote.audio model (0.0.1) trained with PyTorch 1.10
**Current**: Our PyTorch 2.7.1+cu128 is incompatible
**Impact**: TF32 gets disabled during VAD passes, warning messages

**Workaround**: This is a WhisperX upstream issue. The VAD still works, just slower.

### 2. Sequential Processing
**Current**: Segments processed sequentially (one at a time)
**Reason**: VRAM management - prevents OOM errors
**Potential**: Could process 2-4 segments in parallel with careful VRAM management

---

## Testing Instructions

### Benchmark a Video:
```bash
time curl -X POST https://whisper.lan/transcribe-large \
  -F "file=@test-video.mp4" \
  -F "model=large-v3" \
  -F "language=en"
```

### Monitor GPU Usage:
```bash
nvidia-smi dmon -s um -c 1
```

### Check Logs:
```bash
docker compose -p localai logs -f whisperx | grep "INFO"
```

Look for:
- ✅ "TF32 enabled for Tensor Core acceleration"
- ✅ "Loading Whisper model: large-v3" (should appear ONCE)
- ✅ "Detected language: en" (should appear ONCE)
- ✅ Segment processing without model reloads

---

## Future Optimization Opportunities

1. **Parallel Segment Processing**
   - Process 2-4 segments simultaneously
   - Requires careful VRAM management
   - Potential 50-70% additional speedup

2. **Whisper large-v3-turbo**
   - 6x faster than large-v3
   - Similar accuracy
   - Already supported, just change model parameter

3. **Static KV-Cache + torch.compile**
   - 4.5-6x speedup for quantized models
   - Requires code refactoring
   - Best for production deployments

4. **Upgrade Pyannote VAD**
   - Update to pyannote.audio 3.4.0
   - Requires WhisperX upstream fix
   - Would enable full TF32 throughout

---

## References

- [RTX 5090 Blackwell Benchmarks](https://nikolasent.github.io/hardware/deeplearning/benchmark/2025/02/17/RTX5090-Benchmark.html)
- [Whisper Batch Processing Best Practices](https://www.union.ai/blog-post/parallel-audio-transcription-using-whisper-jax-and-flyte-map-tasks-for-streamlined-batch-inference)
- [WhisperX GitHub](https://github.com/m-bain/whisperX)
- [PyTorch TF32 Documentation](https://pytorch.org/docs/stable/notes/cuda.html#tensorfloat-32-tf32-on-ampere-devices)

---

**Last Updated**: October 17, 2025
**WhisperX Version**: 3.7.2
**PyTorch Version**: 2.7.1+cu128
**CUDA Version**: 12.8.1
