"""Render each listed voice's preview clip: the sample drive sentence, cleaned as the apps clean it,
as AAC at 96 kbit/s (64 kbit/s for 24 kHz voices, the most the encoder takes there). Needs macOS for afconvert.
usage: previews.py <packs dir with one folder per pack id> <out dir> [voices.json]
Prints each clip's size and sha256 for shared/voices.json."""
import hashlib, json, os, subprocess, sys
import numpy as np, sherpa_onnx, soundfile as sf

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from clean import clean
from norm import normalize

TEXT = "In half a mile, turn right onto Main Street. Police reported ahead. Then, in 3 miles, take exit 42 toward US 101 South."
packs, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
catalog = json.load(open(sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, "..", "..", "shared", "voices.json")))


def engine(pack, accent):
    d = os.path.join(packs, pack["id"])
    files = {f["role"]: os.path.join(d, f["name"]) for f in pack["files"] if f["role"] not in ("license", "lexicon")}
    if pack["engine"] == "supertonic":
        cfg = dict(supertonic=sherpa_onnx.OfflineTtsSupertonicModelConfig(
            duration_predictor=files["duration_predictor"], text_encoder=files["text_encoder"],
            vector_estimator=files["vector_estimator"], vocoder=files["vocoder"], tts_json=files["tts_json"],
            unicode_indexer=files["unicode_indexer"], voice_style=files["voice_style"]))
    else:
        lex = ",".join(os.path.join(d, n) for n in pack["lexicons"][accent])
        cfg = dict(kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
            model=files["model"], voices=files["voices"], tokens=files["tokens"], lexicon=lex))
    return sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(num_threads=4, **cfg)))


for pack in catalog["packs"]:
    loaded = {}
    for v in pack["voices"]:
        if v["accent"] not in loaded:
            loaded[v["accent"]] = engine(pack, v["accent"])
        gc = sherpa_onnx.GenerationConfig(); gc.sid = v["sid"]; gc.speed = 1.0
        if pack["engine"] == "supertonic":
            gc.num_steps = pack["generation"]["num_steps"]; gc.extra["lang"] = "en"
        a = loaded[v["accent"]].generate(TEXT if pack["text_input"] == "raw" else normalize(TEXT), gc)
        wav = os.path.join(out, f"{v['id']}.wav")
        m4a = os.path.join(out, f"preview.{v['id']}.m4a")
        sf.write(wav, clean(np.asarray(a.samples), a.sample_rate), a.sample_rate, subtype="FLOAT")
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000" if a.sample_rate > 32000 else "64000", "-q", "127", wav, m4a], check=True)
        data = open(m4a, "rb").read()
        print(json.dumps({"id": v["id"], "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}), flush=True)
