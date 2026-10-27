"""Re-quantize Kokoro v1.0 fp32 to int8 except the decoder's generator, and trim it to the 28 English speakers.
usage: requant.py <kokoro-multi-lang-v1_0 dir> <out dir>

The generator (the iSTFTNet vocoder, about 20M of the 81M weights) stays float32. Quantized, it added
steady tones at 4.8 and 9.6 kHz (a fifth and two fifths of the 24 kHz rate) and a 2 to 7 dB higher
noise floor, in our int8 build and in the one sherpa-onnx publishes. Float32 there also fixes the NaN
audio of the stock int8 model on ARM (sherpa-onnx issues #4086 and #3754), and is faster on ARM than
int8 convolutions. See docs/voices.md, "Quality checks"."""
import os, sys
import numpy as np, onnx
from onnxruntime.quantization import QuantType, quantize_dynamic

src_dir, out_dir = sys.argv[1], sys.argv[2]
tmp = out_dir + "/model.tmp.onnx"
src = onnx.load(src_dir + "/model.onnx")
keep_float = [n.name for n in src.graph.node if n.name.startswith("/decoder/generator/")]
assert "/decoder/generator/Conv" in keep_float, "the generator's node names changed"
quantize_dynamic(model_input=src_dir + "/model.onnx", model_output=tmp, weight_type=QuantType.QUInt8,
                 nodes_to_exclude=keep_float)
m = onnx.load(tmp)
meta = {p.key: p.value for p in m.metadata_props}
names = meta["speaker_names"].split(",")[:28]
assert all(n[:2] in ("af", "am", "bf", "bm") for n in names), names
voices = np.fromfile(src_dir + "/voices.bin", dtype=np.float32).reshape(54, 510, 256)
voices[:28].tofile(out_dir + "/voices.bin")
meta.update({
    "n_speakers": "28",
    "speaker_names": ",".join(names),
    "id2speaker": ",".join(f"{i}->{n}" for i, n in enumerate(names)),
    "speaker2id": ",".join(f"{n}->{i}" for i, n in enumerate(names)),
    "has_espeak": "0",
    "language": "English",
    "comment": "Kokoro v1.0, English speakers only (US and UK). Dynamic int8, with the decoder's generator kept in float32. Repacked for CommuteScout Drive.",
})
del m.metadata_props[:]
for k, v in meta.items():
    p = m.metadata_props.add(); p.key = k; p.value = v
onnx.save(m, out_dir + "/model.mixed.onnx")
os.remove(tmp)
print("ok", names)
