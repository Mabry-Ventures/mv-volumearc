import importlib.util, tempfile, pathlib, unittest
source=pathlib.Path(__file__).resolve().parents[1] / 'check-ci-policy.py'
spec=importlib.util.spec_from_file_location('policy',source);policy=importlib.util.module_from_spec(spec);spec.loader.exec_module(policy)
class RunnerPolicy(unittest.TestCase):
 def evaluate(self,body,extra=None):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);w=root/'.github/workflows';w.mkdir(parents=True);(w/'ci.yml').write_text(body)
   for name,value in (extra or {}).items():(w/name).write_text(value)
   return policy.inspect(root)
 def test_ubuntu(self):
  for runner in policy.ALLOWED:self.assertEqual(self.evaluate(f'jobs:\n  test:\n    runs-on: {runner}\n    timeout-minutes: 5\n'),[])
 def test_denied_routing(self):
  for runner in ['macos-latest','macos-26','[self-hosted, macOS]','${{ matrix.os }}','{group: paid}','windows-latest']:
   with self.subTest(runner=runner):self.assertTrue(self.evaluate(f'jobs:\n  test:\n    runs-on: {runner}\n    timeout-minutes: 5\n'))
 def test_timeouts(self):
  for value in ['', '    timeout-minutes: 0\n','    timeout-minutes: 181\n','    timeout-minutes: true\n']:
   self.assertTrue(self.evaluate('jobs:\n  test:\n    runs-on: ubuntu-latest\n'+value))
 def test_duplicate(self):self.assertTrue(self.evaluate('jobs:\n  test:\n    runs-on: macos-latest\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n'))
 def test_external(self):self.assertTrue(self.evaluate('jobs:\n  test:\n    uses: someone/repo/.github/workflows/mac.yml@main\n'))
 def test_local(self):self.assertEqual(self.evaluate('jobs:\n  test:\n    uses: ./.github/workflows/shared.yml\n',{'shared.yml':'jobs:\n  test:\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n'}),[])
 def test_hidden_reusable(self):self.assertTrue(self.evaluate('jobs:\n  test:\n    uses: ./.github/workflows/shared.txt\n',{'shared.txt':'jobs:\n  test:\n    runs-on: macos-latest\n'}))
 def test_reusable_mac(self):self.assertTrue(self.evaluate('jobs:\n  test:\n    uses: ./.github/workflows/shared.yml\n',{'shared.yml':'jobs:\n  test:\n    runs-on: macos-latest\n    timeout-minutes: 5\n'}))
 def test_missing_reusable(self):self.assertTrue(self.evaluate('jobs:\n  test:\n    uses: ./.github/workflows/missing.yml\n'))
 def test_malformed(self):self.assertTrue(self.evaluate('jobs: broken'))
 def test_symlink(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);w=root/'.github/workflows';w.mkdir(parents=True);(root/'other').write_text('jobs: {}');(w/'ci.yml').symlink_to(root/'other');self.assertTrue(policy.inspect(root))
class MissingPolicy(unittest.TestCase):
 def test_missing_or_empty_directory(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d)
   self.assertTrue(policy.inspect(root))
   (root/'.github/workflows').mkdir(parents=True)
   self.assertTrue(policy.inspect(root))
 def test_invalid_structure(self):
  fixture=RunnerPolicy()
  for body in ['', '[]', 'name: empty', 'jobs: {}', 'jobs: []', 'jobs:\n  test: null']:
   with self.subTest(body=body): self.assertTrue(fixture.evaluate(body))

unittest.main()
