"""Exercise the workflow helper against disposable GitHub repository state."""

import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("flux_pr", Path(__file__).parents[1]/"scripts/flux-image-auto-pr.py")
flux_pr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flux_pr)

REPO = "itay-raveh/infra"
MAIN, HEAD, REFRESHED = "a"*40, "b"*40, "c"*40
REF = "refs/heads/flux-image-automation"


def image_file(app="quizmon"):
    if app == "quizmon":
        path = "clusters/shire/apps/quizmon/release/app-chart.yaml"
        field, before, after = "digest", "sha256:"+"1"*64, "sha256:"+"2"*64
    else:
        path = "clusters/shire/apps/wanderbound/app-chart.yaml"
        field, before, after = "tag", "1.14.3", "1.15.0"
    marker = ' # {"$imagepolicy": "flux-system:'+app+':'+field+'"}'
    return {"filename": path, "status": "modified", "additions": 1, "deletions": 1,
            "patch": f"@@ -44 +44 @@\n-      {field}: {before}{marker}\n+      {field}: {after}{marker}"}


class Repository:
    def __init__(self):
        self.pr = {"number": 42, "state": "open", "draft": False, "user": {"login": "infra-flux[bot]"},
                   "head": {"ref": flux_pr.BRANCH, "sha": HEAD, "repo": {"full_name": REPO}},
                   "base": {"ref": "main"}, "auto_merge": None}
        self.head = HEAD
        self.behind = True
        self.files = [image_file()]
        self.commit = {"parents": [{"sha": MAIN}], "author": {"name": "flux", "email": "flux@raveh.dev"},
                       "message": "deploy: update quizmon release"}
        self.move_during_diff = False
        self.move_before_update = False
        self.created = False

    def command(self, *args):
        if args[:2] == ("pr", "list"):
            return json.dumps([{"number": 42}] if self.pr and self.pr["state"] == "open" else [])
        if args[:2] == ("pr", "create"):
            self.created = True
            self.pr = Repository().pr
            return "https://github.com/itay-raveh/infra/pull/42"
        if args[:2] == ("pr", "merge"):
            if "--disable-auto" in args:
                self.pr["auto_merge"] = None
            else:
                expected = args[args.index("--match-head-commit")+1]
                if expected != self.pr["head"]["sha"]:
                    raise ValueError("head changed before auto-merge")
                self.pr["auto_merge"] = {"merge_method": "squash", "head": expected}
            return ""
        if args[0] != "api":
            raise AssertionError(args)
        path = args[1].removeprefix(f"repos/{REPO}/")
        if path == "git/ref/heads/main":
            result = {"object": {"sha": MAIN}}
        elif path == f"git/ref/heads/{flux_pr.BRANCH}":
            result = {"object": {"sha": self.head}}
        elif path.startswith("git/commits/"):
            result = self.commit
        elif path.startswith("compare/"):
            result = {"behind_by": int(self.behind), "files": self.files}
        elif path == "pulls/42/files":
            result = [self.files]
            if self.move_during_diff:
                self.head = self.pr["head"]["sha"] = REFRESHED
        elif path == "pulls/42/update-branch":
            if self.move_before_update:
                self.head = self.pr["head"]["sha"] = REFRESHED
            if f"expected_head_sha={self.head}" not in args:
                raise ValueError("native update rejected moved head")
            self.head = self.pr["head"]["sha"] = REFRESHED
            self.behind = False
            self.commit["parents"].append({"sha": MAIN})
            result = {"message": "Updating pull request branch"}
        elif path == "pulls/42":
            result = self.pr
        else:
            raise AssertionError(args)
        return json.dumps(result)

    def reconcile(self, ref="refs/heads/main", sha=HEAD):
        return flux_pr.reconcile(REPO, ref, sha, self.command)


class WorkflowBehavior(unittest.TestCase):
    def test_behind_branch_refreshes_then_waits_for_new_head_validation(self):
        repo = Repository()
        repo.pr["auto_merge"] = {"merge_method": "squash"}
        self.assertIn("Refresh requested", repo.reconcile())
        self.assertEqual(repo.head, REFRESHED)
        self.assertIsNone(repo.pr["auto_merge"])
        self.assertIn("auto-merge enabled", repo.reconcile(REF, REFRESHED))
        self.assertEqual(repo.pr["auto_merge"]["head"], REFRESHED)
        repo.reconcile(REF, REFRESHED)
        self.assertEqual(repo.head, REFRESHED)

    def test_merged_image_does_not_reopen_on_main_or_refresh_push(self):
        repo = Repository()
        repo.pr["state"] = "closed"
        repo.commit["parents"].append({"sha": MAIN})
        repo.reconcile()
        repo.reconcile(REF)
        self.assertFalse(repo.created)

    def test_only_new_flux_commit_creates_validated_normal_auto_merge(self):
        repo = Repository()
        repo.pr = None
        repo.behind = False
        repo.files.append(image_file("wanderbound"))
        repo.reconcile(REF)
        self.assertTrue(repo.created)
        self.assertEqual(repo.pr["auto_merge"]["head"], HEAD)

    def test_superseded_push_does_not_create_old_update(self):
        repo = Repository()
        repo.pr = None
        self.assertIn("superseded", repo.reconcile(REF, REFRESHED))
        self.assertFalse(repo.created)

    def test_unexpected_or_truncated_diff_holds_existing_auto_merge(self):
        bad_files = [image_file(), image_file(), image_file(), image_file()]
        bad_files[0]["filename"] = ".github/workflows/ci.yaml"
        bad_files[1]["patch"] = None
        bad_files[2]["patch"] = bad_files[2]["patch"].replace("+      digest:", "+      secret:")
        bad_files[3]["patch"] += "\n+      replicas: 0"
        for bad in bad_files:
            with self.subTest(bad=bad):
                repo = Repository()
                repo.files = [bad]
                repo.pr["auto_merge"] = {"merge_method": "squash"}
                with self.assertRaises(ValueError):
                    repo.reconcile()
                self.assertEqual(repo.head, HEAD)
                self.assertIsNone(repo.pr["auto_merge"])

    def test_draft_or_wrong_identity_is_not_managed(self):
        for field in ("draft", "author", "fork"):
            with self.subTest(field=field):
                repo = Repository()
                if field == "draft":
                    repo.pr["draft"] = True
                elif field == "author":
                    repo.pr["user"]["login"] = "someone-else"
                else:
                    repo.pr["head"]["repo"]["full_name"] = "someone/infra"
                before = copy.deepcopy(repo.pr)
                with self.assertRaises(ValueError):
                    repo.reconcile()
                self.assertEqual(repo.pr, before)

    def test_head_races_cannot_overwrite_or_auto_merge_unvalidated_commit(self):
        for race in ("move_during_diff", "move_before_update"):
            with self.subTest(race=race):
                repo = Repository()
                setattr(repo, race, True)
                with self.assertRaises(ValueError):
                    repo.reconcile()
                self.assertEqual(repo.head, REFRESHED)
                self.assertIsNone(repo.pr["auto_merge"])


if __name__ == "__main__":
    unittest.main()
