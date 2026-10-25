"""Re-quantize Kokoro v1.0 fp32 to int8, keeping the two forward-STFT convs in float
(fix for sherpa-onnx issues #4086 / #3754), and trim it to the 28 English speakers."""
import sys, numpy as np, onnx
from onnxruntime.quantization import QuantType, quantize_dynamic

src_dir, out_dir = sys.argv[1], sys.argv[2]
tmp = out_dir + "/model.tmp.onnx"
quantize_dynamic(
    model_input=src_dir + "/model.onnx",
    model_output=tmp,
    weight_type=QuantType.QUInt8,
    nodes_to_exclude=["/decoder/generator/Conv", "/decoder/generator/Conv_1"],
)
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
    "comment": "Kokoro v1.0, English speakers only (US and UK). Dynamic int8 with the forward-STFT convs kept in float32. Repacked for CommuteScout Drive.",
})
del m.metadata_props[:]
for k, v in meta.items():
    p = m.metadata_props.add(); p.key = k; p.value = v
onnx.save(m, out_dir + "/model.int8.onnx")
import os; os.remove(tmp)
print("ok", names)
