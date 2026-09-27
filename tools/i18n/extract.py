#!/usr/bin/env python3
"""Build lang/<domain>.pot, the translation template, from the calls to
IN.T and IN.N in Bartleby's Vim scripts. See Localization_README.md.

Usage, from the root of the repository:
  python3 tools/i18n/extract.py           write the template
  python3 tools/i18n/extract.py --check   exit 1 when the template is
                                          not up to date
  python3 tools/i18n/extract.py --domain  print the text domain

The text domain is PLUGIN_NAME in lowercase, read from
import/bartleby/variables/constants.vim, as TEXT_DOMAIN is there. So the
name is defined once, in that file.

The text of a call must be a double-quoted literal in the call itself.
Any other argument, such as a variable or an interpolated string, is an
error, because its text cannot be extracted and so never gets
translated.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONSTANTS = os.path.join(ROOT, "import", "bartleby", "variables", "constants.vim")


def domain():
    text = open(CONSTANTS, encoding="utf-8").read()
    return re.search(r"^export const PLUGIN_NAME: string = '([^']+)'", text, re.M).group(1).lower()


POT = os.path.join(ROOT, "lang", domain() + ".pot")
SOURCES = ["plugin", "autoload", "import", "syntax", "ftdetect"]
DQ = r'"((?:[^"\\]|\\.)*)"'
CALL = re.compile(r"\bIN\.(T|N)\(")
T_CALL = re.compile(r"\bIN\.T\(\s*" + DQ + r"\s*\)")
N_CALL = re.compile(r"\bIN\.N\(\s*" + DQ + r"\s*,\s*" + DQ + r"\s*,")
HEADER = '''msgid ""
msgstr ""
"Project-Id-Version: {project}\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
'''


def scan():
    entries = {}
    errors = []
    for folder in SOURCES:
        for path in sorted(glob.glob(os.path.join(ROOT, folder, "**", "*.vim"), recursive=True)):
            rel = os.path.relpath(path, ROOT)
            text = open(path, encoding="utf-8").read()
            for call in CALL.finditer(text):
                line_start = text.rfind("\n", 0, call.start()) + 1
                if text[line_start:call.start()].lstrip().startswith("#"):
                    continue
                lnum = text.count("\n", 0, call.start()) + 1
                # The arguments of a call may continue on the next lines.
                rest = re.sub(r"\n\s*\\?", " ", text[call.start():call.start() + 600])
                m = (T_CALL if call.group(1) == "T" else N_CALL).match(rest)
                if not m:
                    errors.append(f"{rel}:{lnum}: IN.{call.group(1)} needs literal double-quoted text")
                    continue
                entries.setdefault(m.groups(), []).append(f"{rel}:{lnum}")
    return entries, errors


def render(entries):
    out = [HEADER.format(project=domain())]
    for key in sorted(entries, key=lambda k: entries[k][0]):
        out.append("#: " + " ".join(entries[key]))
        if len(key) == 2:
            out.append(f'msgid "{key[0]}"\nmsgid_plural "{key[1]}"\nmsgstr[0] ""\nmsgstr[1] ""\n')
        else:
            out.append(f'msgid "{key[0]}"\nmsgstr ""\n')
    return "\n".join(out)


def main():
    if "--domain" in sys.argv:
        print(domain())
        return 0
    entries, errors = scan()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    text = render(entries)
    if "--check" in sys.argv:
        current = open(POT, encoding="utf-8").read() if os.path.exists(POT) else ""
        if current != text:
            print(f"{os.path.relpath(POT, ROOT)} is not up to date: run python3 tools/i18n/extract.py", file=sys.stderr)
            return 1
        return 0
    os.makedirs(os.path.dirname(POT), exist_ok=True)
    open(POT, "w", encoding="utf-8").write(text)
    print(f"{POT}: {len(entries)} messages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
