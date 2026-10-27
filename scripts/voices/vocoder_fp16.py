"""Convert Supertone's float32 Supertonic 2 vocoder to float16 weights with float32 inputs and outputs.
usage: vocoder_fp16.py <supertonic-2 onnx/vocoder.onnx> <out vocoder.fp16.onnx>

The sherpa-onnx int8 vocoder raised the noise floor under speech by 5 to 9 dB, heard as hiss and a
rough, recorded sound. float16 measures the same as float32, at half its size and the same speed.
The pack's other three models stay the sherpa-onnx int8 build: quantizing them costs nothing we
could measure. See docs/voices.md, "Quality checks"."""
import os, sys
import onnx
from onnxconverter_common import float16

src, out = sys.argv[1], sys.argv[2]
onnx.save(float16.convert_float_to_float16(onnx.load(src), keep_io_types=True), out)
print(out, f"{os.path.getsize(out) / 1e6:.1f} MB")
