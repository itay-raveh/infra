#!/usr/bin/env python3
import json
from pathlib import Path
import re
import subprocess

paths = [Path("README.md"), Path("bootstrap/README.md"), *sorted(Path("docs").glob("*.md"))]
subprocess.run(["lychee", "--offline", "--include-fragments", *map(str, paths)], check=True)
tasks = {task["name"] for task in json.loads(subprocess.check_output(["mise", "tasks", "--json"]))}
fences = re.compile(
    r"^(?P<indent> {0,3})(?P<fence>(?P<char>`|~)(?P=char){2,})[ \t]*(?P<language>[^\n]*)\n"
    r"(?P<body>.*?)(?:^ {0,3}(?P=fence)(?P=char)*[ \t]*(?:\n|$)|\Z)",
    re.M | re.S,
)
for path in paths:
    text = path.read_text()
    for block in fences.finditer(text):
        if block["language"].strip() not in {"bash", "sh"}:
            continue
        source = re.sub(rf"^ {{0,{len(block['indent'])}}}", "", block["body"], flags=re.M)
        source = "\n" * text.count("\n", 0, block.start("body")) + source
        result = subprocess.run(["bash", "-n"], input=source, text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(result.stderr.replace("bash:", f"{path}:"))
    for task in re.findall(r"\bmise run ([\w:-]+)", text):
        if task not in tasks:
            raise SystemExit(f"{path}: unknown mise task {task}")
print(f"Documentation links, shell syntax and task names passed ({len(paths)} files).")
