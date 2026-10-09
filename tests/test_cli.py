"""CLI regression tests; use `python3 -m unittest discover -s tests -v`."""
import hashlib, json, os, pathlib, subprocess, tempfile, unittest, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
CLI=ROOT/'cli'/'lub'
class TestLUB(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base=pathlib.Path(self.temp.name)
        self.project=self.base/'SampleApp'; self.project.mkdir()
        self.package=self.base/'update'; (self.package/'payload').mkdir(parents=True)
        self.env=dict(os.environ,HOME=str(self.base))
    def prepare(self,dst='new.txt',payload=b'after',src='payload/data.txt'):
        (self.package/'payload'/'data.txt').write_bytes(payload)
        manifest={'formatVersion':1,'project':'SampleApp','version':'1.0.0','files':[{'source':src,'destination':dst,'sha256':hashlib.sha256(payload).hexdigest()}]}
        (self.package/'bridge-manifest.json').write_text(json.dumps(manifest))
    def cli(self,*args,success=True):
        p=subprocess.run(['python3',str(CLI),'--json',*map(str,args)],capture_output=True,text=True,env=self.env)
        if success: self.assertEqual(p.returncode,0,p.stderr)
        else: self.assertNotEqual(p.returncode,0,p.stdout)
        return json.loads(p.stdout or p.stderr)
    def test_roundtrip_new_file(self):
        self.prepare(); self.cli('validate',self.package,'--project',self.project)
        self.cli('apply',self.package,'--project',self.project,'--approve')
        self.assertEqual((self.project/'new.txt').read_bytes(),b'after')
        self.cli('rollback','--project',self.project,'--approve')
        self.assertFalse((self.project/'new.txt').exists())
    def test_roundtrip_existing_file(self):
        (self.project/'new.txt').write_bytes(b'before'); self.prepare()
        self.cli('apply',self.package,'--project',self.project,'--approve')
        self.cli('rollback','--project',self.project,'--approve')
        self.assertEqual((self.project/'new.txt').read_bytes(),b'before')
    def test_apply_requires_approval(self):
        self.prepare(); self.cli('apply',self.package,'--project',self.project,success=False)
        self.assertFalse((self.project/'new.txt').exists())
    def test_reject_traversal(self):
        self.prepare(dst='../escape.txt')
        self.cli('validate',self.package,'--project',self.project,success=False)
        self.assertFalse((self.base/'escape.txt').exists())
    def test_reject_bad_hash(self):
        self.prepare(); (self.package/'payload'/'data.txt').write_bytes(b'tampered')
        self.cli('validate',self.package,'--project',self.project,success=False)
    def test_reject_symlink_escape(self):
        outside=self.base/'outside'; outside.mkdir()
        (self.project/'other').symlink_to(outside,target_is_directory=True)
        self.prepare(dst='other/new.txt')
        self.cli('validate',self.package,'--project',self.project,success=False)
    def test_zip_package(self):
        self.prepare(); archive=self.base/'update.zip'
        with zipfile.ZipFile(archive,'w') as z:
            for f in self.package.rglob('*'):
                if f.is_file(): z.write(f,f.relative_to(self.package))
        self.cli('apply',archive,'--project',self.project,'--approve')
        self.assertEqual((self.project/'new.txt').read_bytes(),b'after')
    def test_build_failure_json(self):
        info=self.cli('build','--project',self.project,'--exec','/usr/bin/false',success=False)
        # Exit failures return structured stdout, not an exception.
        self.assertTrue(info.get('success') is False or 'error' in info)
if __name__=='__main__': unittest.main()
