"""Unit tests for bin/jeans-instability. Run: python3 -m unittest discover -s test"""
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(HERE, "..", "bin", "jeans-instability")
loader = importlib.machinery.SourceFileLoader("jeans", path)
spec = importlib.util.spec_from_loader("jeans", loader)
jeans = importlib.util.module_from_spec(spec)
loader.exec_module(jeans)


class GithubRepo(unittest.TestCase):
    def test_accepted_forms(self):
        for url in ("https://github.com/o/r", "https://github.com/o/r.git", "https://github.com/o/r/",
                    "https://www.github.com/o/r/tree/main", "git@github.com:o/r.git", "ssh://git@github.com/o/r.git"):
            self.assertEqual(jeans.github_repo(url), ("o", "r"), url)

    def test_rejected_forms(self):
        for url in ("https://gitlab.com/o/r", "https://github.com/o", "https://user:pw@github.com/o/r",
                    "https://github.com/-o/r", "https://github.com/o/..", "file:///github.com/o/r",
                    "https://github.com.evil.example/o/r", "https://omastorm.com", ""):
            self.assertIsNone(jeans.github_repo(url), url)


class OriginUrl(unittest.TestCase):
    def test_only_origin(self):
        cfg = '[core]\n\turl = nope\n[remote "upstream"]\n\turl = https://github.com/a/b\n[remote "origin"]\n\turl = https://github.com/c/d.git\n'
        self.assertEqual(jeans.origin_url(cfg), "https://github.com/c/d.git")

    def test_missing(self):
        self.assertEqual(jeans.origin_url("[core]\n\tbare = false\n"), "")


class ReadFile(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dirfd = os.open(self.tmp.name, os.O_RDONLY | os.O_DIRECTORY)

    def tearDown(self):
        os.close(self.dirfd)
        self.tmp.cleanup()

    def write(self, name, data):
        with open(os.path.join(self.tmp.name, name), "wb") as f:
            f.write(data)

    def test_regular(self):
        self.write("m.json", b"{}")
        self.assertEqual(jeans.read_file(self.dirfd, "m.json", 10), b"{}")

    def test_too_large(self):
        self.write("m.json", b"x" * 11)
        self.assertIsNone(jeans.read_file(self.dirfd, "m.json", 10))

    def test_symlink_refused(self):
        self.write("real", b"secret")
        os.symlink(os.path.join(self.tmp.name, "real"), os.path.join(self.tmp.name, "link"))
        self.assertIsNone(jeans.read_file(self.dirfd, "link", 100))

    def test_fifo_does_not_block(self):
        os.mkfifo(os.path.join(self.tmp.name, "fifo"))
        self.assertIsNone(jeans.read_file(self.dirfd, "fifo", 100))

    def test_absent(self):
        self.assertIsNone(jeans.read_file(self.dirfd, "nope", 100))


class Clean(unittest.TestCase):
    def test_strips_controls_and_caps(self):
        self.assertEqual(jeans.clean("a\x1b[31mb\u202ec" + "x" * 300, 10), "a[31mbcxxx")
        self.assertEqual(jeans.clean(None), "")


class Star(unittest.TestCase):
    def setUp(self):
        self.calls = []
        test = self

        class FakeGitHub:
            def star(self, name):
                test.calls.append(name)

        self.saved = (jeans.GitHub, jeans.gh_token, jeans.survey)
        jeans.GitHub = lambda token: FakeGitHub()
        jeans.gh_token = lambda: "x" * 40
        jeans.survey = lambda github=None: {"login": "me", "plugins": [
            {"repo": "Alice/Widget", "starred": False, "note": ""},
            {"repo": "bob/done", "starred": True, "note": ""},
            {"repo": "", "starred": None, "note": "no GitHub repository"},
        ]}

    def tearDown(self):
        jeans.GitHub, jeans.gh_token, jeans.survey = self.saved

    def test_stars_listed_repo_by_canonical_name(self):
        self.assertEqual(jeans.star("alice/widget"), {"starred": "Alice/Widget"})
        self.assertEqual(self.calls, ["Alice/Widget"])

    def test_refuses_anything_else(self):
        for target in ("bob/done", "torvalds/linux", "../x", "a/b/c", "-o/r", ""):
            with self.assertRaises(jeans.Failure, msg=target):
                jeans.star(target)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
