"""What the apps do to a voice's samples before they play: the reference for NeuralPlan.clean (Swift)
and NeuralAudio.clean (Kotlin).

- A 30 Hz high-pass. Kokoro's output sits on a DC offset of about 0.025, which clicks where a clip
  starts and ends.
- A gain that brings speech to -20 dBFS RMS, so every voice is about as loud as the next, at most 4x
  and never past a 0.95 peak.
- 5 ms fades at both ends."""
import math
import numpy as np

TARGET_RMS = 0.1
MAX_GAIN = 4.0
MAX_PEAK = 0.95
HIGHPASS_HZ = 30.0
FADE_S = 0.005


def clean(x: np.ndarray, sr: int) -> np.ndarray:
    x = np.nan_to_num(np.asarray(x, dtype=np.float64))
    if x.size == 0:
        return x.astype(np.float32)
    r = math.exp(-2 * math.pi * HIGHPASS_HZ / sr)
    y = np.empty_like(x)
    prev_x, prev_y = x[0], 0.0
    for i, v in enumerate(x):
        prev_y = v - prev_x + r * prev_y
        prev_x = v
        y[i] = prev_y
    # Speech level: the RMS of the 20 ms frames within 30 dB of the loudest one.
    n = max(1, int(0.02 * sr))
    frames = [y[i:i + n] for i in range(0, len(y), n)]
    rms = np.array([math.sqrt(float(np.mean(f * f))) for f in frames])
    loud = rms[rms >= rms.max() * 10 ** (-30 / 20)] if rms.max() > 0 else rms
    level = math.sqrt(float(np.mean(loud * loud))) if loud.size else 0.0
    peak = float(np.max(np.abs(y)))
    gain = 1.0 if level <= 0 or peak <= 0 else min(TARGET_RMS / level, MAX_GAIN, MAX_PEAK / peak)
    y *= gain
    k = min(int(FADE_S * sr), len(y) // 2)
    if k > 0:
        ramp = np.arange(k) / k
        y[:k] *= ramp
        y[len(y) - k:] *= ramp[::-1]
    return y.astype(np.float32)
