"""Convert CMUdict (ARPAbet) entries to misaki phonemes for words the Kokoro lexicon lacks.
usage: cmu2misaki.py <cmudict.dict> <lexicon-us-en.txt> <lexicon-gb-en.txt> <out_dir> [extra_words.txt]"""
import re, sys, collections

US_V = {"AA": "ɑ", "AE": "æ", "AO": "ɔ", "AW": "W", "AY": "I", "EH": "ɛ", "EY": "A", "IH": "ɪ", "IY": "i", "OW": "O", "OY": "Y", "UH": "ʊ", "UW": "u"}
GB_V = {"AA": "ɒ", "AE": "a", "AO": "ɔː", "AW": "W", "AY": "I", "EH": "ɛ", "EY": "A", "IH": "ɪ", "IY": "iː", "OW": "Q", "OY": "Y", "UH": "ʊ", "UW": "uː"}
C = {"B": "b", "CH": "ʧ", "D": "d", "DH": "ð", "F": "f", "G": "ɡ", "HH": "h", "JH": "ʤ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ",
     "P": "p", "R": "ɹ", "S": "s", "SH": "ʃ", "T": "t", "TH": "θ", "V": "v", "W": "w", "Y": "j", "Z": "z", "ZH": "ʒ"}
VOWELS = set(US_V) | {"AH", "ER"}

def convert(arpa, gb=False):
    out = []
    ph = arpa.split()
    for i, p in enumerate(ph):
        base, stress = re.match(r"([A-Z]+)(\d?)", p).groups()
        mark = {"1": "ˈ", "2": "ˌ"}.get(stress, "")
        nxt = re.match(r"([A-Z]+)(\d?)", ph[i + 1]).groups() if i + 1 < len(ph) else (None, None)
        nxt2 = re.match(r"([A-Z]+)", ph[i + 2]).group() if i + 2 < len(ph) else None
        prev = re.match(r"([A-Z]+)", ph[i - 1]).group() if i > 0 else None
        if base in VOWELS:
            if base in ("AH", "IH") and stress == "0" and nxt[0] in ("Z", "D") and nxt2 is None and not gb: v = "ᵻ"
            elif base == "AH" and stress == "0" and nxt[0] in ("L", "N") and (nxt2 is None or nxt2 not in VOWELS) and i > 0 and not gb: v = "ᵊ"
            elif gb and base == "IY" and stress == "0" and nxt[0] is None: v = "i"
            elif base == "AH": v = "ə" if stress == "0" else "ʌ"
            elif base == "ER":
                if gb: v = ("ə" if stress == "0" else "ɜː") + ("ɹ" if nxt[0] in VOWELS else "")
                else: v = "əɹ" if stress == "0" else "ɜɹ"
            else: v = (GB_V if gb else US_V)[base]
            out.append(mark + v)
        else:
            if gb and base == "R" and (i + 1 == len(ph) or re.match(r"[A-Z]+", ph[i + 1]).group() not in VOWELS):
                continue  # non-rhotic: no r before a consonant or at the end
            if not gb and base == "T" and prev is not None and (prev in VOWELS or prev == "R") and nxt[0] in VOWELS and nxt[1] == "0":
                out.append("ɾ"); continue
            out.append(C[base])
    return "".join(out)

def load_lex(path):
    d = {}
    for line in open(path, encoding="utf-8"):
        parts = line.rstrip("\n").split(" ")
        if len(parts) > 1 and "||" not in parts: d[parts[0]] = "".join(parts[1:])
    return d

cmu_path, us_path, gb_path, out_dir = sys.argv[1:5]
cmu = collections.OrderedDict()
for line in open(cmu_path, encoding="utf-8"):
    line = line.split("#")[0].strip()
    if not line: continue
    w, pron = line.split(" ", 1)
    if "(" in w: continue  # keep the first pronunciation only
    if not re.fullmatch(r"[a-z][a-z'.\-]*", w): continue
    cmu[w] = pron
for kind, path, gb in (("us", us_path, False), ("gb", gb_path, True)):
    lex = load_lex(path)
    both = [w for w in cmu if w in lex]
    exact = sum(convert(cmu[w], gb) == lex[w] for w in both)
    nostress = sum(re.sub("[ˈˌ]", "", convert(cmu[w], gb)) == re.sub("[ˈˌ]", "", lex[w]) for w in both)
    print(f"{kind}: lexicon {len(lex)}, cmudict {len(cmu)}, overlap {len(both)}, exact match {exact/len(both):.1%}, ignoring stress {nostress/len(both):.1%}")
    added = [(w, convert(cmu[w], gb)) for w in cmu if w not in lex]
    with open(f"{out_dir}/lexicon-{kind}-en-extra.txt", "w", encoding="utf-8", newline="\n") as f:
        for w, p in added: f.write(w + " " + " ".join(p) + "\n")
    print(f"{kind}: wrote {len(added)} entries")
