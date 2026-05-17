import re
import pandas as pd
from .config_analysis import PLACEHOLDERS, PHRASE_MAP

def normalize_text(text: str) -> str:
    if pd.isna(text):
        return ""

    for src, tgt in PLACEHOLDERS.items():
        text = text.replace(src, tgt)

    text = text.lower()

    for pat, repl in PHRASE_MAP:
        text = re.sub(pat, repl, text)

    text = re.sub(r"http\S+", "", text)
    text = re.sub(r"[^a-z_<> ]", " ", text)
    text = re.sub(r"\s+", " ", text)

    return text.strip()