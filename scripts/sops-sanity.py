#!/usr/bin/env python3
"""Check publishable secret structure without decrypting production files."""

import argparse
import base64
import binascii
import json
from pathlib import Path
import re
import subprocess
import sys


CIPHERTEXT = re.compile(
    r"ENC\[AES256_GCM,data:([A-Za-z0-9+/=]*),iv:([A-Za-z0-9+/=]+),"
    r"tag:([A-Za-z0-9+/=]+),type:(str|int|float|bool|bytes)\]"
)
VENDOR = "clusters/shire/infrastructure/controllers/barman-cloud-plugin/manifest.yaml"


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate mapping key")
        result[key] = value
    return result


def documents(content):
    parsed = subprocess.run(
        ["yq", "-p=yaml", "-o=json", "-I=0", "."], input=content,
        text=True, capture_output=True, check=False,
    )
    if parsed.returncode:
        raise ValueError("invalid YAML or JSON")
    return [json.loads(line, object_pairs_hook=unique_object)
            for line in parsed.stdout.splitlines() if line.strip()]


def encrypted(value):
    match = CIPHERTEXT.fullmatch(value) if isinstance(value, str) else None
    if not match:
        return False
    try:
        data, iv, tag = (base64.b64decode(part, validate=True) for part in match.groups()[:3])
        return bool(data) and len(iv) == 32 and len(tag) == 16
    except binascii.Error:
        return False


def leaves(value):
    if isinstance(value, dict):
        for child in value.values():
            yield from leaves(child)
    elif isinstance(value, list):
        for child in value:
            yield from leaves(child)
    else:
        yield value


def mappings(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from mappings(child)
    elif isinstance(value, list):
        for child in value:
            yield from mappings(child)


def check_encrypted(path, docs, rules):
    rule = next((rule for rule in rules if re.search(rule["path_regex"], path)), None)
    if rule is None:
        raise ValueError("no matching creation rule")
    if len(docs) != 1 or not isinstance(docs[0], dict):
        raise ValueError("expected one encrypted document")
    document = docs[0]
    metadata = document.get("sops", {})
    allowed = {"age", "mac", "version", "lastmodified", "encrypted_regex", "unencrypted_suffix"}
    if not isinstance(metadata, dict) or set(metadata) - allowed:
        raise ValueError("unsupported SOPS metadata")
    if not encrypted(metadata.get("mac")) or not metadata.get("version") or not metadata.get("lastmodified"):
        raise ValueError("missing or malformed SOPS metadata")
    recipients = metadata.get("age", [])
    expected = sorted(part.strip() for part in rule["age"].split(","))
    if not isinstance(recipients, list) or sorted(item.get("recipient", "") for item in recipients) != expected:
        raise ValueError("recipients do not match .sops.yaml")
    for recipient in recipients:
        envelope = recipient.get("enc", "")
        if not envelope.startswith("-----BEGIN AGE ENCRYPTED FILE-----\n") or not envelope.rstrip().endswith("-----END AGE ENCRYPTED FILE-----"):
            raise ValueError("missing age key envelope")
    if path.startswith("clusters/"):
        if document.get("kind") != "Secret" or document.get("apiVersion") != "v1":
            raise ValueError("expected a Kubernetes Secret")
        if metadata.get("encrypted_regex") != rule.get("encrypted_regex") or "unencrypted_suffix" in metadata:
            raise ValueError("incorrect encryption selector")
        payload = {key: document[key] for key in ("data", "stringData") if key in document}
    else:
        if metadata.get("unencrypted_suffix") != "_unencrypted" or "encrypted_regex" in metadata:
            raise ValueError("incorrect encryption selector")
        payload = {key: value for key, value in document.items() if key != "sops"}
    values = list(leaves(payload))
    if not values or not all(encrypted(value) for value in values):
        raise ValueError("secret values must contain complete SOPS ciphertext")


def check_plaintext(path, docs):
    for document in docs:
        for item in mappings(document):
            if item.get("kind") != "Secret":
                continue
            if path == VENDOR and item.get("data", {}).keys() == {"SIDECAR_IMAGE"} and not item.get("stringData"):
                try:
                    image = base64.b64decode("".join(item["data"]["SIDECAR_IMAGE"].split()), validate=True).decode()
                    if re.fullmatch(r"ghcr\.io/cloudnative-pg/plugin-barman-cloud-sidecar:v[0-9.]+", image):
                        continue
                except (ValueError, UnicodeError):
                    pass
            raise ValueError("plaintext Kubernetes Secret")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="inspect the Git index, including .sops.yaml")
    args = parser.parse_args()

    def read(path):
        if args.staged:
            return subprocess.check_output(["git", "show", ":" + path], text=True)
        return Path(path).read_text()

    rules = documents(read(".sops.yaml"))[0]["creation_rules"]
    files = subprocess.check_output(["git", "ls-files", "-z", "--cached"], text=True).split("\0")
    failed = False
    for path in sorted(set(files)):
        if not path or path == ".sops.yaml":
            continue
        is_encrypted = ".sops." in Path(path).name
        if not is_encrypted and not (path.startswith("clusters/") and Path(path).suffix in (".yaml", ".yml", ".json")):
            continue
        try:
            docs = documents(read(path))
            if is_encrypted:
                check_encrypted(path, docs, rules)
            else:
                check_plaintext(path, docs)
        except (ValueError, KeyError, TypeError, AttributeError, OSError, subprocess.CalledProcessError) as error:
            print(f"{path}: {error}", file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError):
        sys.exit("Could not read the SOPS rules or Git index")
