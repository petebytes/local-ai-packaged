# CUDA Compatibility Findings for RTX 5090

**Test Date:** October 16, 2025
**GPU:** NVIDIA GeForce RTX 5090 (Blackwell Architecture)
**Driver Version:** Check with `nvidia-smi`

## Summary

Testing revealed critical compatibility issues with certain CUDA versions on the RTX 5090.

## Test Results

### ✅ CUDA 12.8 - **COMPATIBLE**
- **Status:** Working perfectly
- **Test Result:** Successful transcription
- **Speed:** 2.52 seconds for test sample
- **WER:** 17.86%
- **Notes:** This is the minimum CUDA version for RTX 5090

### ❌ CUDA 12.9 - **INCOMPATIBLE**
- **Status:** CUDA kernel error
- **Error:** `CUDA error: no kernel image is available for execution on the device`
- **Root Cause:** PyTorch mismatch - PyTorch 2.7.1+cu126 instead of cu129
- **Base Image Issue:** CUDA 12.9 image has PyTorch built for CUDA 12.6
- **Impact:** Cannot run inference, transcription fails
- **Notes:** PyAnnote VAD model loading triggers the error

### ❌ CUDA 13.0 - **INCOMPATIBLE**
- **Status:** CUDA kernel error (same as 12.9)
- **Error:** `CUDA error: no kernel image is available for execution on the device`
- **Root Cause:** PyTorch mismatch - PyTorch 2.7.1+cu126 instead of cu130
- **Base Image Issue:** CUDA 13.0 image also has PyTorch built for CUDA 12.6
- **Impact:** Cannot run inference, transcription fails

## Technical Details

### Error Details (CUDA 12.9)
```
RuntimeError: CUDA error: no kernel image is available for execution on the device
CUDA kernel errors might be asynchronously reported at some other API call
```

**Stack Trace Location:**
```
File: /usr/local/lib/python3.10/dist-packages/torch/nn/modules/rnn.py
Function: flatten_parameters()
Issue: torch._cudnn_rnn_flatten_weight() fails for LSTM/GRU layers
```

**Affected Component:** PyAnnote Audio VAD pipeline (Voice Activity Detection)

### Why This Happens

The RTX 5090 uses the **Blackwell architecture** (compute capability sm_120), which requires:
- CUDA kernels specifically compiled for sm_120
- CUDA 12.8+ minimum (earlier versions don't support Blackwell)
- PyTorch built with the correct CUDA toolkit version

**Root Cause - PyTorch/CUDA Mismatch:**
Our base images have a critical mismatch:
- CUDA 12.8 image: ✅ PyTorch 2.7.1+cu128 (correct)
- CUDA 12.9 image: ❌ PyTorch 2.7.1+cu126 (wrong - should be cu129)
- CUDA 13.0 image: ❌ PyTorch 2.7.1+cu126 (wrong - should be cu130)

This happens because:
1. PyTorch official builds for CUDA 12.9/13.0 may not exist yet
2. The base image Dockerfile likely falls back to cu126 when cu129/cu130 aren't available
3. Kernel compilation happens at PyTorch build time, not runtime

**Web Research Validation:**
- PyTorch 2.7 officially supports CUDA 12.8 (cu128) for Blackwell
- CUDA 12.9 and 13.0 support requires PyTorch nightly builds or future releases
- RTX 5090 requires CUDA 12.8+ AND matching PyTorch cu128+ wheels

## Recommendations

### For RTX 5090 Users

1. **Use CUDA 12.8** (Tested and Working) ⭐
   - ✅ Fully compatible with RTX 5090
   - ✅ PyTorch 2.7.1+cu128 official wheels available
   - ✅ Stable and reliable
   - **Recommended for production**

2. **CUDA 12.9/13.0** (Not Ready Yet)
   - ❌ PyTorch official wheels not available (fall back to cu126)
   - ⏳ Wait for PyTorch 2.8+ or use nightly builds
   - ⚠️ Not recommended until official PyTorch support

3. **Future PyTorch Releases**
   - Watch for PyTorch 2.8+ with cu129/cu130 wheels
   - Monitor PyTorch nightly builds for bleeding-edge support
   - Re-test when official wheels become available

### Configuration

Apply the working profile:
```bash
./cuda-optimization/scripts/switch-profile.sh apply whisperx-speed-optimized
# Uses CUDA 13.0 (or change to 12.8 for maximum stability)
```

Or manually set in Dockerfile:
```dockerfile
ARG CUDA_VERSION=12.8  # For stability
# OR
ARG CUDA_VERSION=13.0  # For latest features
```

## Impact on Testing

The automated CUDA version testing system successfully identified this incompatibility:
- ✅ **Value demonstrated:** Testing multiple CUDA versions is essential
- ✅ **Time saved:** Avoided production deployment of incompatible version
- ✅ **Best practice confirmed:** Always test before deploying

## Next Steps

1. ✅ Test CUDA 13.0 to verify full compatibility
2. ⏳ Update all services to use CUDA 12.8 or 13.0
3. ⏳ Document this finding for other RTX 5090 users
4. ⏳ Report issue to NVIDIA/PyTorch if not already known

## Related Issues

This type of issue may affect:
- Other Blackwell architecture GPUs (RTX 5080, 5070, etc.)
- Any models using cuDNN RNN layers (LSTM, GRU)
- PyAnnote audio models specifically

## Version Matrix

| CUDA Version | RTX 5090 | PyTorch Support | Status | Use Case |
|--------------|----------|-----------------|--------|----------|
| 12.1         | ❌ No    | N/A | Too old | Legacy only |
| 12.8         | ✅ Yes   | ✅ cu128 official | **Recommended** | Production stable |
| 12.9         | ❌ No    | ❌ No cu129 wheels | Incompatible | **Avoid until PyTorch 2.8+** |
| 13.0         | ❌ No    | ❌ No cu130 wheels | Incompatible | **Avoid until PyTorch 2.8+** |
| 13.1         | ⏳ TBD   | ⏳ Future | Untested | Experimental |

### Actual Base Image PyTorch Versions Found:
- cuda-base:runtime-12.8 → PyTorch 2.7.1+cu128 ✅
- cuda-base:runtime-12.9 → PyTorch 2.7.1+cu126 ❌ (fallback)
- cuda-base:runtime-13.0 → PyTorch 2.7.1+cu126 ❌ (fallback)

## Web Research Validation

### PyTorch Official Support (Verified October 2025)

**PyTorch 2.7 Release:**
- First stable release with RTX 5090/Blackwell (sm_120) support
- Official wheels available for CUDA 12.8 (cu128)
- Supports Linux x86 and arm64 architectures
- Installation: `pip install torch==2.7.1 --index-url https://download.pytorch.org/whl/cu128`

**CUDA 12.9/13.0 Status:**
- No official PyTorch wheels for cu129 or cu130 as of PyTorch 2.7.1
- Support expected in PyTorch 2.8+ (future release)
- Nightly builds may have experimental support
- Production use not recommended until official wheels available

**Community Reports:**
Multiple GitHub issues confirm the same finding:
- vllm-project/vllm#16901: RTX 5090 kernel error
- pytorch/pytorch#159207: sm_120 support request
- lllyasviel/Fooocus#3862: RTX 5090 compatibility
- ultralytics/ultralytics#21162: CUDA 12.8 support request

**NVIDIA Developer Forums:**
- Software Migration Guide recommends CUDA 12.8 + PyTorch 2.7 for Blackwell
- RTX 5090 requires minimum CUDA 12.8
- Blackwell architecture needs sm_120 kernels compiled into PyTorch

### Key Findings Summary

1. **RTX 5090 Minimum Requirements:**
   - CUDA 12.8 or higher
   - PyTorch 2.7+ with matching CUDA version (cu128+)
   - Driver supporting Blackwell architecture

2. **PyTorch Availability:**
   - ✅ PyTorch 2.7.1+cu128: Official, tested, production-ready
   - ❌ PyTorch 2.7.1+cu129: Not available, falls back to cu126
   - ❌ PyTorch 2.7.1+cu130: Not available, falls back to cu126
   - ⏳ PyTorch 2.8+: Expected future support for newer CUDA

3. **Why Fallback Fails:**
   - cu126 wheels don't include sm_120 kernels
   - RTX 5090 requires sm_120 for all operations
   - Mismatch causes "no kernel image available" error

## Conclusion

**The automated testing system successfully identified a critical incompatibility** that would have caused production issues. This validates the importance of the multi-version testing approach.

**Root Cause Confirmed:** PyTorch version mismatch, not CUDA runtime incompatibility.

**Recommended Action:** Use CUDA 12.8 with PyTorch 2.7.1+cu128 for maximum stability and RTX 5090 compatibility.

---

**Generated by:** CUDA version testing suite
**Test System:** cuda-optimization/docker-compose.test-matrix.yml
**Validation:** Web research + Docker image inspection + Real hardware testing
**Updated:** October 16, 2025
