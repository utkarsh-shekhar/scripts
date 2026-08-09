#!/usr/bin/env python3
"""
hyprwhspr dictation cleaner.

Pipeline (all deterministic where it matters):
  1. regex_clean      : remove fillers (um/uh/stutters) WITHOUT touching real words
  2. llm_clean        : gemma3:1b (Ollama) adds punctuation/capitalization only,
                        grounded to keep words verbatim
  3. post_fix         : fix common model blemishes (glued words, spacing)
  4. convert_numbers  : "three hundred million" -> 300,000,000 (verbatim span swap)

Falls back gracefully at any stage; never loses the dictation. Designed for
hyprwhspr's post_transcription_hook (hard 5s hook timeout).
"""
import sys, re, json, urllib.request

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "gemma3:1b"
LLM_BUDGET_S = 4.0  # must stay under hyprwhspr's hard 5.0s hook timeout

# ---------------------------------------------------------------- regex fallback
FILLERS = [
    r"\buh\b", r"\bum\b", r"\ber\b", r"\bah\b", r"\beh\b", r"\bhmm\b", r"\bhm\b",
    r"\bmm\b", r"\bmhm\b", r"\byou know\b", r"\bkinda\b", r"\bkind of\b",
    r"\bsort of\b", r"\bsorta\b", r"\bbasically\b", r"\btotally\b", r"\bliterally\b",
]

def regex_clean(t):
    for f in FILLERS:
        t = re.sub(r"(?i)\s*" + f + r"\s*", " ", t)
    t = re.sub(r",\s*,+", ",", t)
    t = re.sub(r"\s+,\s*", ", ", t)
    t = re.sub(r",\s*\.", ".", t)
    t = re.sub(r",\s*(?=[,.;!?])", "", t)
    t = re.sub(r"\b(\w+)\s+\1\b", r"\1", t, flags=re.I)
    t = re.sub(r"^\s*(so|and|but|well|then)\s*[,]?\s*", "", t, flags=re.I)
    t = re.sub(r"[\s,]*\b(you know|right|okay?|yeah|yep)\s*$", "", t, flags=re.I)
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r"\s+([,.;:!?])", r"\1", t)
    t = t.replace(" , ", ", ").strip().lstrip(",;: ").strip()
    return t

# --------------------------------------------------------------- LLM stage
LLM_SYSTEM = (
    "You add punctuation and capitalization to plain text, and fix garbled names.\n"
    "KNOWN VOCABULARY (correct any of these that appear jumbled/misheard in the text):\n"
    "- Person names: Utkarsh Shekhar (the speaker), Ritwika Maity, Suman Sharma, \n"
    "  Jahnvi Shekhar, Apoorva Shekhar.\n"
    "  (Spelling notes: 'Ritwika Maity' — last name is 'Maity', not 'Miti/Mitai'. \n"
    "   'Apoorva' — spelled A-p-o-o-r-v-a, not 'Apoura/Apoorvaa/Aparva'. \n"
    "   'Jahnvi' — not 'Jhanvi/Jahnavi'.)\n"
    "- Places: Thakurdwara, Palampur, Kangra, Himachal (Himachal Pradesh).\n"
    "RULES:\n"
    "1. The text is already clean of fillers — there are no 'um'/'uh' to remove.\n"
    "2. VERBATIM for ordinary words: keep every word EXACTLY as given. Never \n"
    "reword, reorder, add, or delete a word; never replace a word with a synonym.\n"
    "3. NAME FIXES ONLY: if a KNOWN person/place name above is spelled wrong or \n"
    "sounds jumbled (e.g. 'Utkar Sakh', 'Ritika Maitya', 'Jhanvi', 'Apurva', \n"
    "'Takurduara', 'Palampurr', 'Kangraa', 'Himal'), correct it to the exact \n"
    "canonical spelling listed above. Fix ONLY these known names/places — never \n"
    "change any other word or proper noun.\n"
    "4. Add standard punctuation (.,!?;:) and correct capitalization ONLY. Split \n"
    "run-on sentences where grammar demands, using only the existing words.\n"
    "5. Output ONLY the punctuated text — no quotes, no explanation.\n"
)

FEWSHOT = (
    "Examples:\n"
    "Input: so I want to get the report to the client today\n"
    "Output: So I want to get the report to the client today.\n\n"
    "Input: we should check the numbers before we submit\n"
    "Output: We should check the numbers before we submit.\n\n"
    "Input: can you forward this to Priya please\n"
    "Output: Can you forward this to Priya, please?\n\n"
    "Input: utkar shakar and ritika miti are coming to palamphur\n"
    "Output: Utkarsh Shekhar and Ritwika Maity are coming to Palampur.\n"
)

def llm_clean(text):
    prompt = FEWSHOT + "\nNow punctuate this text:\n" + text
    payload = {
        "model": MODEL,
        "system": LLM_SYSTEM,
        "prompt": prompt,
        "stream": False,
        "keep_alive": -1,
        "options": {"temperature": 0.2},
    }
    req = urllib.request.Request(
        OLLAMA_URL, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=LLM_BUDGET_S) as resp:
        result = json.loads(resp.read().decode())
    out = (result.get("response") or "").strip()
    out = re.sub(r"\s*[\s,.;:]*\b(okay|ok|right|yeah|yep)\s*\.?\s*$", "", out, flags=re.I)
    return out

# --------------------------------------------------------------- post-fix
def post_fix(t):
    if not t:
        return t
    # Re-separate words the model glued together ("tofinalize" -> "to finalize")
    t = re.sub(r"(?i)\b(to|the|and|is|of|for|a|we|i|you|they|our|in|on|with|can|then)\b(?=[a-z])", r"\1 ", t)
    t = re.sub(r"\bThousand\b", "thousand", t)
    t = re.sub(r"\bHundred\b", "hundred", t)
    t = re.sub(r"\bMillion\b", "million", t)
    t = re.sub(r"\bBillion\b", "billion", t)
    t = re.sub(r"[ \t]+", " ", t).strip()
    t = re.sub(r"\s+([,.;:!?])", r"\1", t)
    t = re.sub(r"([.!?])(?=[A-Za-z])", r"\1 ", t)
    return t

# ------------------------------------------------------------ number conversion
_NUM_SYS = {
    'zero':0,'one':1,'two':2,'three':3,'four':4,'five':5,'six':6,'seven':7,'eight':8,'nine':9,
    'ten':10,'eleven':11,'twelve':12,'thirteen':13,'fourteen':14,'fifteen':15,'sixteen':16,
    'seventeen':17,'eighteen':18,'nineteen':19,'twenty':20,'thirty':30,'forty':40,'fifty':50,
    'sixty':60,'seventy':70,'eighty':80,'ninety':90,'hundred':100,'thousand':1000,
    'million':1000000,'billion':1000000000,'point':'.'
}
_DEC_WORDS=['zero','one','two','three','four','five','six','seven','eight','nine']
_UNITS={'zero','one','two','three','four','five','six','seven','eight','nine'}
_TEENS={'ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen'}
_TENS={'twenty','thirty','forty','fifty','sixty','seventy','eighty','ninety'}
_SCALES={'hundred','thousand','million','billion'}

def _nf(words):
    n=[_NUM_SYS[w] for w in words]
    if len(n)==4: return (n[0]*n[1])+n[2]+n[3]
    if len(n)==3: return n[0]*n[1]+n[2]
    if len(n)==2: return n[0]*n[1] if 100 in n else n[0]+n[1]
    return n[0]

def _is_time(ws):
    if any(w in _SCALES for w in ws): return False
    return len(ws)>=2 and ws[0] in _UNITS|_TEENS and ws[1] in _TENS

def _w2n(sentence):
    raw=sentence.replace('-',' ').lower().split()
    if _is_time(raw): raise ValueError("time")
    ns=sentence.replace('-',' ').lower().strip()
    if ns.isdigit(): return int(ns)
    clean=[w for w in ns.split() if w in _NUM_SYS]
    if not clean: raise ValueError("no numbers")
    if any(clean.count(s)>1 for s in ('thousand','million','billion','point')): raise ValueError("redundant")
    dec=[]
    if 'point' in clean:
        dec=clean[clean.index('point')+1:]; clean=clean[:clean.index('point')]
    bi=clean.index('billion') if 'billion' in clean else -1
    mi=clean.index('million') if 'million' in clean else -1
    ti=clean.index('thousand') if 'thousand' in clean else -1
    total=0
    if clean:
        if len(clean)==1: total+=_NUM_SYS[clean[0]]
        else:
            if bi>-1: total+=_nf(clean[0:bi])*1000000000
            if mi>-1: total+=_nf(clean[bi+1:mi] if bi>-1 else clean[0:mi])*1000000
            if ti>-1: total+=_nf(clean[mi+1:ti] if mi>-1 else (clean[bi+1:ti] if bi>-1 and mi==-1 else clean[0:ti]))*1000
            if ti>-1 and ti!=len(clean)-1: h=_nf(clean[ti+1:])
            elif mi>-1 and mi!=len(clean)-1: h=_nf(clean[mi+1:])
            elif bi>-1 and bi!=len(clean)-1: h=_nf(clean[bi+1:])
            elif ti==-1 and mi==-1 and bi==-1: h=_nf(clean)
            else: h=0
            total+=h
    if dec: total+=float('0.'+''.join(str(_NUM_SYS[w]) for w in dec if w in _DEC_WORDS))
    return total

_NUMWORDS=set(_NUM_SYS.keys())

WORD_RE = re.compile(r"[A-Za-z']+")

def convert_numbers(text):
    # Walk words (ignoring hyphen as separator within number phrases)
    toks = WORD_RE.finditer(text)  # word tokens with spans
    words = [(m.start(), m.end(), m.group(0)) for m in toks if m.group(0)]
    out = []
    last = 0
    i = 0
    n = len(words)
    while i < n:
        start, end, w = words[i]
        low = w.lower().rstrip(".,;:")
        if low in _NUMWORDS:
            # gather phrase: number words, hyphens, and 'and'
            phrase_tokens = [words[i]]
            j = i + 1
            prev_end = end
            while j < n:
                ws, we, wj = words[j]
                gap = text[prev_end:ws]
                wj_low = wj.lower().rstrip(".,;:")
                if wj_low == 'and':
                    if j+1 < n and words[j+1][2].lower().rstrip(".,;:") in _NUMWORDS:
                        phrase_tokens.append(words[j]); phrase_tokens.append(words[j+1]); j += 2; prev_end = words[j-1][1]; continue
                    break
                # allow hyphenated: if gap is a single hyphen (with optional spaces) -> glue
                if wj_low in _NUMWORDS:
                    phrase_tokens.append(words[j]); prev_end = we; j += 1; continue
                if re.fullmatch(r"\s*-\s*", gap):
                    # hyphen joins: include next only if it's a number word (handled above) else stop
                    break
                break
            # phrase text span
            p_start = phrase_tokens[0][0]
            p_end = phrase_tokens[-1][1]
            joined = ' '.join(t[2].rstrip(".,;:") for t in phrase_tokens)
            try:
                v = _w2n(joined)
                if isinstance(v, float) and v == int(v): v = int(v)
                repl = format(v, ',') if isinstance(v, int) else str(v)
                out.append(text[last:p_start])
                out.append(repl)
                last = p_end
                i = j
                continue
            except Exception:
                # Time phrase or unparseable number: leave the whole phrase verbatim.
                i = j
                continue
        i += 1
    out.append(text[last:])
    return ''.join(out)
def main():
    raw = sys.stdin.read().strip()
    if not raw:
        return
    no_fill = regex_clean(raw)
    cleaned = None
    try:
        cleaned = llm_clean(no_fill)
    except Exception as e:
        sys.stderr.write(f"llm cleaner unavailable ({e}); using regex output\n")
        cleaned = None
    if not (cleaned and cleaned.strip()):
        cleaned = no_fill
    print(convert_numbers(post_fix(cleaned)))

if __name__ == "__main__":
    main()
