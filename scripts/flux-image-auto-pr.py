"""Keep the existing Flux image PR current without bypassing required checks."""

import json
import os
import re
import subprocess
import sys

BRANCH = "flux-image-automation"
SETTERS = {
    "clusters/shire/apps/quizmon/release/app-chart.yaml": re.compile(
        r'( +digest: )(sha256:[a-f0-9]{64})( # \{"\$imagepolicy": "flux-system:quizmon:digest"\})'
    ),
    "clusters/shire/apps/wanderbound/app-chart.yaml": re.compile(
        r'( +tag: )([0-9]+\.[0-9]+\.[0-9]+)( # \{"\$imagepolicy": "flux-system:wanderbound:tag"\})'
    ),
}


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True).strip()


def validate_files(files):
    if not files or len(files) > len(SETTERS):
        raise ValueError("Expected only existing Flux image setters")
    for file in files:
        pattern = SETTERS.get(file["filename"])
        if pattern is None or file["status"] != "modified":
            raise ValueError("Unexpected file in the Flux image PR")
        patch = file.get("patch") or ""
        removed = [line[1:] for line in patch.splitlines() if line.startswith("-")]
        added = [line[1:] for line in patch.splitlines() if line.startswith("+")]
        if file["additions"] != 1 or file["deletions"] != 1 or len(removed) != 1 or len(added) != 1:
            raise ValueError("Expected one image setter change per file")
        before, after = pattern.fullmatch(removed[0]), pattern.fullmatch(added[0])
        if not before or not after or before[1] != after[1] or before[3] != after[3] or before[2] == after[2]:
            raise ValueError("Changes outside an existing image setter")


def reconcile(repo, push_ref, push_sha, command=gh):
    def api(path, *args):
        return json.loads(command("api", f"repos/{repo}/{path}", *args))

    def checked_pr(number):
        pr = api(f"pulls/{number}")
        if pr["state"] != "open":
            return None
        if (pr["draft"] or pr["user"]["login"] != "infra-flux[bot]"
                or pr["head"]["ref"] != BRANCH or pr["head"]["repo"]["full_name"] != repo
                or pr["base"]["ref"] != "main"):
            raise ValueError("Refusing to manage a PR outside the existing Flux bot and branches")
        pages = api(f"pulls/{number}/files", "--paginate", "--slurp")
        try:
            validate_files([file for page in pages for file in page])
        except ValueError:
            if pr.get("auto_merge"):
                command("pr", "merge", str(number), "--disable-auto")
            raise
        latest = api(f"pulls/{number}")
        if latest["state"] != "open":
            return None
        if latest["head"]["sha"] != pr["head"]["sha"]:
            raise ValueError("PR head moved during validation; wait for its push workflow")
        return pr

    prs = json.loads(command("pr", "list", "--head", BRANCH, "--base", "main", "--state", "open", "--json", "number"))
    if len(prs) > 1:
        raise ValueError("More than one open Flux image PR")
    if not prs:
        # A main push after auto-merge must not reopen the old image update.
        if push_ref != f"refs/heads/{BRANCH}":
            return "No open image PR to refresh"
        head = api(f"git/ref/heads/{BRANCH}")["object"]["sha"]
        if head != push_sha:
            return "A newer Flux push superseded this run"
        commit = api(f"git/commits/{head}")
        # Native branch refreshes have two parents; they must not create a new PR.
        if (len(commit["parents"]) != 1 or commit["author"]["name"] != "flux" or commit["author"]["email"] != "flux@raveh.dev"
                or commit["message"] not in {"deploy: update quizmon release", "deploy: update wanderbound release"}):
            return "Not a new Flux image commit"
        main = api("git/ref/heads/main")["object"]["sha"]
        validate_files(api(f"compare/{main}...{head}")["files"])
        url = command("pr", "create", "--head", BRANCH, "--base", "main", "--title", "flux: image automation updates",
                      "--body", "Automated image bumps from the Flux image-automation-controller.")
        number = int(url.rsplit("/", 1)[1])
    else:
        number = prs[0]["number"]
    pr = checked_pr(number)
    if pr is None:
        return "Image PR already closed"
    head = pr["head"]["sha"]
    main = api("git/ref/heads/main")["object"]["sha"]
    if api(f"compare/{main}...{head}")["behind_by"]:
        if pr.get("auto_merge"):
            command("pr", "merge", str(number), "--disable-auto")
        api(f"pulls/{number}/update-branch", "--method", "PUT", "--raw-field", f"expected_head_sha={head}")
        # The app-token push starts the next run and fresh required CI.
        return "Refresh requested; the new branch push will validate and enable auto-merge"
    command("pr", "merge", str(number), "--auto", "--squash", "--match-head-commit", head)
    return "Normal auto-merge enabled for the validated image PR head"


if __name__ == "__main__":
    try:
        print(reconcile(os.environ["GH_REPO"], os.environ["FLUX_PUSH_REF"], os.environ["FLUX_PUSH_SHA"]))
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"Flux image PR requires attention: {error}", file=sys.stderr)
        sys.exit(1)
