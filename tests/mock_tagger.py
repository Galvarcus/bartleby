#!/usr/bin/env python3
"""Mock part-of-speech tagger for Bartleby's tests. Speaks the protocol of
tools/pos/spacy_tagger.py without spaCy: each word gets its tag from the
fixed TAGS table (NOUN when unknown), and "was <word>ed" is passive.
Needs only Python 3, so CI can run it."""

import json
import re
import sys

TAGS = {
    "the": "DET", "a": "DET", "was": "AUX", "by": "ADP", "him": "PRON",
    "she": "PRON", "and": "CCONJ", "quietly": "ADV", "opened": "VERB",
    "walked": "VERB", "red": "ADJ",
}

for line in sys.stdin:
    request = json.loads(line)
    data = request["text"].encode("utf-8")
    tokens = []
    for match in re.finditer(rb"[A-Za-z]+", data):
        word = match.group().decode("utf-8").lower()
        tokens.append([match.start(), match.end(), TAGS.get(word, "NOUN")])
    passive = [[m.start(), m.end()] for m in re.finditer(rb"\bwas [a-z]+ed\b", data)]
    sys.stdout.write(json.dumps({"id": request["id"], "tokens": tokens, "passive": passive}) + "\n")
    sys.stdout.flush()
