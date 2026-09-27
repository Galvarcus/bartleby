#!/usr/bin/env python3
"""Bartleby part-of-speech tagger, using spaCy.

Bartleby starts this script once and keeps it running. Protocol, one
JSON object per line in each direction:

    stdin:  {"id": 7, "text": "The door was opened."}
    stdout: {"id": 7,
             "tokens": [[0, 3, "DET"], [4, 8, "NOUN"], ...],
             "passive": [[9, 19]]}

"tokens" holds one [start, end, tag] entry per word, with a Universal POS
tag (NOUN, VERB, ADJ, ADV, PRON, DET, ADP, CCONJ, SCONJ, AUX, ...).
"passive" holds the span of each passive construction, from its first
auxiliary to its main verb ("was opened", "has been eaten"). Offsets are
UTF-8 byte offsets into "text", end exclusive, so Vim can use them as
column positions directly.

Usage: spacy_tagger.py [model]    (default model: en_core_web_sm)
"""

import json
import sys


def byte_offsets(text):
    """Byte offset of every character position, plus the end."""
    offsets = [0]
    for ch in text:
        offsets.append(offsets[-1] + len(ch.encode("utf-8")))
    return offsets


def ud_passive_spans(doc, offsets):
    """Passive spans for models that label the passive auxiliary auxpass
    or aux:pass, as the English model does. The span runs from the first
    auxiliary of the verb, of any aux label, to the verb."""
    spans = []
    for verb in doc:
        auxes = [c for c in verb.children if c.dep_.startswith("aux")]
        if not any(c.dep_ in ("auxpass", "aux:pass") for c in auxes):
            continue
        start = min(c.idx for c in auxes)
        end = verb.idx + len(verb.text)
        spans.append([offsets[start], offsets[end]])
    return spans


# Passive rules by the model's language, nlp.lang. A language without a
# rule returns no passive spans, and its language file sets
# tagger_passive to false, so Bartleby hides the Passive mode. See
# Localization_README.md.
PASSIVE_RULES = {
    "en": ud_passive_spans,
}


def passive_spans(doc, offsets):
    rule = PASSIVE_RULES.get(doc.lang_)
    return rule(doc, offsets) if rule else []


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "en_core_web_sm"
    try:
        import spacy
        nlp = spacy.load(model, disable=["ner", "lemmatizer"])
    except Exception as error:
        print(f"spaCy could not load {model}: {error}", file=sys.stderr)
        sys.exit(1)

    for line in sys.stdin:
        request = json.loads(line)
        text = request["text"]
        offsets = byte_offsets(text)
        doc = nlp(text)
        tokens = [
            [offsets[t.idx], offsets[t.idx + len(t.text)], t.pos_]
            for t in doc
            if not t.is_space
        ]
        reply = {"id": request["id"], "tokens": tokens,
                 "passive": passive_spans(doc, offsets)}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
