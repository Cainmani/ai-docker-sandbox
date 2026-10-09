#!/usr/bin/env python3
"""Behavioral contracts, isolated from live tools/auth and process admission."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class AgentContracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='ai-docker-agents-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.proc = self.root / 'proc'
        self.proc.mkdir()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin)+':/usr/bin:/bin', AI_MAINTENANCE_PROC_ROOT=str(self.proc))

    def tool(self, name, body):
        p = self.bin / name
        p.write_text('#!/bin/bash\n'+body+'\n')
        p.chmod(0o755)

    def run_bash(self, code, **kwargs):
        return subprocess.run(['/bin/bash', '-c', code], env=self.env, text=True, capture_output=True, **kwargs)

    def lock(self, mode):
        return self.run_bash(f'source "{ROOT}/docker/lib/maintenance.sh"; ai_maintenance_acquire {mode}')

    def test_session_admission_cannot_race_maintenance(self):
        # Exclusive maintenance is already admitted when a new session arrives.
        code = f'source "{ROOT}/docker/lib/maintenance.sh"; ai_maintenance_acquire exclusive || exit $?; echo locked; read -r _'
        holder = subprocess.Popen(['/bin/bash', '-c', code], env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), 'locked')
            self.assertEqual(self.lock('shared').returncode, 75)
            self.assertEqual(self.lock('exclusive').returncode, 75)
        finally:
            holder.communicate('done\n', timeout=5)
        self.assertEqual(self.lock('shared').returncode, 0)

    def test_managed_session_blocks_mutation_and_allows_another_session(self):
        code = f'source "{ROOT}/docker/lib/maintenance.sh"; ai_maintenance_acquire shared; echo locked; read -r _'
        holder = subprocess.Popen(['/bin/bash','-c',code],env=self.env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), 'locked')
            self.assertEqual(self.lock('exclusive').returncode, 75)
            self.assertEqual(self.lock('shared').returncode, 0)
        finally:
            holder.communicate('done\n',timeout=5)

    def test_manual_agent_blocks_mutation(self):
        process = self.proc / '123'
        process.mkdir()
        (process/'cmdline').write_bytes(b'/home/user/.npm-global/bin/codex\x00\x00')
        result = self.lock('exclusive')
        self.assertEqual(result.returncode,75)
        self.assertIn('active-session',result.stderr)

    def test_missing_flock_is_failure(self):
        # Missing PATH has no flock; check fails before mkdir or any mutation.
        env = dict(self.env,PATH=str(self.bin))
        result=subprocess.run(['/bin/bash','-c',f'source "{ROOT}/docker/lib/maintenance.sh"; ai_maintenance_acquire exclusive'],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,69)

    def test_keyring_status_does_not_need_auth_file_and_secrets_are_not_output(self):
        for name in ('claude','codex','gh'):
            self.tool(name, 'echo "secret-account-token@example.invalid"; exit 0')
        result=subprocess.run(['/bin/bash',str(ROOT/'docker/agent_health.sh')],env=self.env,capture_output=True,text=True)
        self.assertIn('AUTH_codex=ready',result.stdout)
        self.assertNotIn('secret',result.stdout+result.stderr)
        self.assertFalse((self.home/'.codex/auth.json').exists())

    def test_failed_status_is_unable_to_verify(self):
        self.tool('codex','if [ "$1" = --version ]; then exit 0; fi; exit 1')
        result=subprocess.run(['/bin/bash',str(ROOT/'docker/agent_health.sh')],env=self.env,capture_output=True,text=True)
        self.assertIn('TOOL_codex=ready',result.stdout)
        self.assertIn('AUTH_codex=unable-to-verify',result.stdout)
        self.assertNotIn('expired',result.stdout)

    def repair_fixture(self, fail=False):
        for name in ('claude','gh','node','python3'):
            self.tool(name,'echo "version 1.0.0"; exit 0')
        self.tool('pip3','exit 0')
        self.tool('sudo','echo "UNEXPECTED-SUDO" >&2; exit 9')
        code = 'exit 1' if fail else 'exit 0'
        self.tool('npm', '''if [ "${1:-}" = install ] && [ "${2:-}" = --prefix ]; then
mkdir -p "$3/node_modules/.bin"
printf '#!/bin/bash\\necho "codex 0.146.0"\\nexit 0\\n' > "$3/node_modules/.bin/codex"
chmod +x "$3/node_modules/.bin/codex"
'''+code+'''
fi
exit 0''')
        directory=self.home/'.npm-global/bin'
        directory.mkdir(parents=True)
        original=directory/'codex'
        original.write_text('#!/bin/bash\nexit 1\n' if not fail else '#!/bin/bash\necho "old codex"\nexit 0\n')
        original.chmod(0o755)
        settings=self.home/'.codex/config.toml'
        settings.parent.mkdir()
        settings.write_text('model = "user-choice"\n')
        result=subprocess.run(['/bin/bash',str(ROOT/'docker/install_cli_tools.sh'),'--repair-tool','codex'],env=self.env,capture_output=True,text=True)
        self.assertEqual(settings.read_text(),'model = "user-choice"\n')
        self.assertNotIn('UNEXPECTED-SUDO',result.stdout+result.stderr)
        return result, original

    def test_selected_repair_fixes_broken_binary_without_other_installations(self):
        result, launcher=self.repair_fixture()
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue(launcher.is_symlink())
        self.assertIn('TOOL_codex=ok',(self.home/'.cli_tools_installed').read_text())

    def test_failed_replacement_preserves_existing_launcher(self):
        result, launcher=self.repair_fixture(fail=True)
        self.assertEqual(result.returncode,1)
        self.assertFalse(launcher.is_symlink())
        self.assertIn('old codex',launcher.read_text())

    def test_directory_selected_after_legacy_startup_and_metacharacters_are_data(self):
        # Use a public fixture under /workspace so the real containment check runs.
        with tempfile.TemporaryDirectory(prefix='.agent-fixture-',dir=ROOT) as fixture:
            selected=Path(fixture)/'Unicode-λ spaces \' $ ; % ^ ! " & |'
            selected.mkdir()
            shell=self.root/'startup'
            shell.write_text('cd -- '+str(ROOT)+'\n')
            script=self.root/'session.sh'
            script.write_text((ROOT/'docker/agent_session.sh').read_text().replace('/workspace',str(ROOT)).replace('/usr/local/lib/maintenance.sh',str(ROOT/'docker/lib/maintenance.sh')))
            self.tool('claude','printf "AGENT_PWD=%s\\n" "$PWD"')
            self.tool('bash','printf "SHELL_OPEN=%s\\n" "$PWD"')
            result=subprocess.run(['/bin/bash','--noprofile','--rcfile',str(shell),'-i','-c','exec /bin/bash "$1" claude "$2"','bash',str(script),str(selected)],env=self.env,capture_output=True,text=True)
            self.assertIn('AGENT_PWD='+str(selected),result.stdout)
            self.assertEqual(result.returncode,0)
            missing=subprocess.run(['/bin/bash',str(script),'claude',str(selected/'missing')],env=self.env,capture_output=True,text=True)
            self.assertIn('SHELL_OPEN=',missing.stdout)
            self.assertNotIn('AGENT_PWD=',missing.stdout)
            self.assertIn('missing',missing.stderr)
            escape=Path(fixture)/'escape'
            escape.symlink_to('/tmp',target_is_directory=True)
            result=subprocess.run(['/bin/bash',str(script),'claude',str(escape)],env=self.env,capture_output=True,text=True)
            self.assertNotIn('AGENT_PWD=',result.stdout)
            self.assertIn('SHELL_OPEN=',result.stdout)

if __name__=='__main__':
    unittest.main()
