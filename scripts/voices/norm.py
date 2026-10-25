"""The text rules the apps should apply before a lexicon engine (Kokoro) speaks.
Kept tiny on purpose: it is the reference for the Swift and Kotlin ports."""
import re
ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()

def words(n: int) -> str:
    if n < 20: return ONES[n]
    if n < 100: return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    if n < 1000:
        return ONES[n // 100] + " hundred" + ("" if n % 100 == 0 else " " + words(n % 100))
    if n < 1_000_000:
        return words(n // 1000) + " thousand" + ("" if n % 1000 == 0 else " " + words(n % 1000))
    return " ".join(ONES[int(d)] for d in str(n))

def route_number(n: str) -> str:
    # Road numbers are said the way drivers say them: 101 "one oh one", 80 "eighty", 405 "four oh five".
    i = int(n)
    if i < 100: return words(i)
    if len(n) == 3 and n[1] == "0": return ONES[int(n[0])] + " oh " + ONES[int(n[2])]
    if len(n) == 3: return ONES[int(n[0])] + " " + words(int(n[1:]))
    return words(i)

ROUTE = re.compile(r"\b(I|US|CA|SR|Hwy|Highway|Route|Interstate)[- ]?(\d{1,3})\b")
PREFIX = {"I": "I", "US": "U S", "CA": "C A", "SR": "State Route", "Hwy": "Highway", "Highway": "Highway", "Route": "Route", "Interstate": "Interstate"}
ABBR = {r"\bSt\b": "Street", r"\bAve\b": "Avenue", r"\bBlvd\b": "Boulevard", r"\bRd\b": "Road", r"\bDr\b": "Drive",
        r"\bN\b": "North", r"\bS\b": "South", r"\bE\b": "East", r"\bW\b": "West", r"\bmph\b": "miles per hour",
        r"\bCHP\b": "C H P", r"\bmi\b": "miles", r"\bkm\b": "kilometers", r"\bft\b": "feet"}

IRREGULAR = {"one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth", "nine": "ninth", "twelve": "twelfth"}

def ordinal(n: int) -> str:
    # 3rd "third", 21st "twenty first", 112th "one hundred twelfth": only the last word changes.
    *head, last = words(n).split(" ")
    if last in IRREGULAR: last = IRREGULAR[last]
    elif last.endswith("y"): last = last[:-1] + "ieth"
    else: last += "th"
    return " ".join(head + [last])

def letters(s: str) -> str:
    # A short all-caps run is a code, said letter by letter: G5 "G five".
    return " ".join(s) if s.isupper() and len(s) <= 3 else s

def normalize(t: str) -> str:
    for k, v in ABBR.items(): t = re.sub(k, v, t)
    t = ROUTE.sub(lambda m: PREFIX[m.group(1)] + " " + route_number(m.group(2)), t)
    t = re.sub(r"\b(\d+)(st|nd|rd|th)\b", lambda m: ordinal(int(m.group(1))), t)
    t = re.sub(r"(\d+)\.(\d+)", lambda m: words(int(m.group(1))) + " point " + " ".join(ONES[int(d)] for d in m.group(2)), t)
    t = re.sub(r"\b([A-Za-z]+)(\d+)\b", lambda m: letters(m.group(1)) + " " + words(int(m.group(2))), t)
    t = re.sub(r"\b(\d+)([A-Za-z])\b", lambda m: words(int(m.group(1))) + " " + m.group(2), t)
    t = re.sub(r"\d+", lambda m: words(int(m.group(0))), t)
    return t

if __name__ == "__main__":
    import sys
    for line in sys.argv[1:]: print(normalize(line))
