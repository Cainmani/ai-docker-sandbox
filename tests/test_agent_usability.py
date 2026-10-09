#!/usr/bin/env python3
"""Behavioral contracts, isolated from live tools/auth and process admission."""
import os
import json
import shutil
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

    def test_unrelated_long_running_cli_js_does_not_block_updates(self):
        process=self.proc/'123'
        process.mkdir()
        (process/'cmdline').write_bytes(b'/usr/bin/node\x00/workspace/unrelated/cli.js\x00')
        self.assertEqual(self.lock('exclusive').returncode,0)
        (process/'cmdline').write_bytes(b'/usr/bin/node\x00/home/user/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js\x00')
        self.assertEqual(self.lock('exclusive').returncode,75)

    def test_missing_flock_is_failure(self):
        # Missing PATH has no flock; check fails before mkdir or any mutation.
        env = dict(self.env,PATH=str(self.bin))
        result=subprocess.run(['/bin/bash','-c',f'source "{ROOT}/docker/lib/maintenance.sh"; ai_maintenance_acquire exclusive'],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,69)

    def test_keyring_status_does_not_need_auth_file_and_secrets_are_not_output(self):
        for name in ('claude','codex','gh'):
            self.tool(name, 'echo "secret-account-token@example.invalid"; exit 0')
        result=subprocess.run(['/bin/bash',str(ROOT/'docker/agent_health.sh')],env=self.env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
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
        self.tool('npm', '''if [ "${1:-}" = install ] && [ "${3:-}" = --prefix ]; then
mkdir -p "$4/bin" "$4/lib/node_modules/@openai/codex/bin"
printf '#!/bin/bash\\necho "codex 0.146.0"\\nexit 0\\n' > "$4/lib/node_modules/@openai/codex/bin/codex.js"
chmod +x "$4/lib/node_modules/@openai/codex/bin/codex.js"
ln -s ../lib/node_modules/@openai/codex/bin/codex.js "$4/bin/codex"
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
        self.assertEqual(os.readlink(launcher), '../lib/node_modules/@openai/codex/bin/codex.js')
        self.assertFalse(list((self.home/'.npm-global').glob('.codex-repair.*')))
        self.assertIn('TOOL_codex=ok',(self.home/'.cli_tools_installed').read_text())

    def test_failed_replacement_preserves_existing_launcher(self):
        result, launcher=self.repair_fixture(fail=True)
        self.assertEqual(result.returncode,1)
        self.assertFalse(launcher.is_symlink())
        self.assertIn('old codex',launcher.read_text())

    def test_repair_remains_owned_and_replaceable_by_real_npm(self):
        npm = shutil.which('npm')
        if not npm: self.skipTest('npm unavailable')
        for name in ('claude','gh','python3','pip3'):
            self.tool(name,'echo "version 1.0.0"; exit 0')
        package=self.root/'package'
        package.mkdir()
        dependency=self.root/'platform-package'
        dependency.mkdir()
        (dependency/'package.json').write_text(json.dumps({'name':'@openai/codex-platform','version':'1.0.0','main':'index.js'}))
        (dependency/'index.js').write_text('module.exports = true;\n')
        packed_dependency=subprocess.run([npm,'pack','--pack-destination',str(self.root)],cwd=dependency,env=self.env,capture_output=True,text=True)
        self.assertEqual(packed_dependency.returncode,0,packed_dependency.stderr)
        dependency_archive=self.root/packed_dependency.stdout.strip().splitlines()[-1]
        (package/'package.json').write_text(json.dumps({'name':'@openai/codex','version':'0.146.0','bin':{'codex':'bin/codex.js'},'optionalDependencies':{'@openai/codex-platform':'file:'+str(dependency_archive)}}))
        (package/'bin').mkdir()
        (package/'bin/codex.js').write_text('#!/usr/bin/env node\nrequire("@openai/codex-platform"); console.log("codex 0.146.0")\n')
        packed=subprocess.run([npm,'pack','--pack-destination',str(self.root)],cwd=package,env=self.env,capture_output=True,text=True)
        self.assertEqual(packed.returncode,0,packed.stderr)
        archive=self.root/packed.stdout.strip().splitlines()[-1]
        # Only redirect the package download to a local fixture. The npm global
        # install, dependency layout, links and subsequent replacement are real.
        self.tool('npm', 'args=("$@"); if [ "${1:-}" = install ]; then args[${#args[@]}-1]="'+str(archive)+'"; fi; exec "'+npm+'" "${args[@]}"')
        result=subprocess.run(['/bin/bash',str(ROOT/'docker/install_cli_tools.sh'),'--repair-tool','codex'],env=self.env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        prefix=self.home/'.npm-global'
        listed=subprocess.run([npm,'ls','-g','--prefix',str(prefix),'--json'],env=self.env,capture_output=True,text=True)
        self.assertEqual(json.loads(listed.stdout)['dependencies']['@openai/codex']['version'],'0.146.0')
        metadata=json.loads((package/'package.json').read_text())
        metadata['version']='0.146.1'
        (package/'package.json').write_text(json.dumps(metadata))
        (package/'bin/codex.js').write_text('#!/usr/bin/env node\nrequire("@openai/codex-platform"); console.log("codex 0.146.1")\n')
        packed=subprocess.run([npm,'pack','--pack-destination',str(self.root)],cwd=package,env=self.env,capture_output=True,text=True)
        self.assertEqual(packed.returncode,0,packed.stderr)
        updated=subprocess.run([npm,'install','-g','--prefix',str(prefix),str(self.root/packed.stdout.strip().splitlines()[-1])],env=self.env,capture_output=True,text=True)
        self.assertEqual(updated.returncode,0,updated.stderr)
        version=subprocess.run([str(prefix/'bin/codex'),'--version'],env=self.env,capture_output=True,text=True)
        self.assertIn('0.146.1',version.stdout)
        self.assertFalse(list(prefix.glob('.codex-repair.*')))

    def test_terminal_and_after_agent_keep_bashrc_environment(self):
        self.tool('claude','printf "AGENT_PWD=%s\\n" "$PWD"')
        (self.home/'.bashrc').write_text('cd "'+str(ROOT)+'"\nalias check-updates="echo CHECK_ALIAS"\n9router() { echo ROUTER_WRAPPER; }\necho STATUS_LINE\n')
        script=self.root/'session.sh'
        script.write_text((ROOT/'docker/agent_session.sh').read_text().replace('/workspace',str(ROOT)).replace('/usr/local/lib/maintenance.sh',str(ROOT/'docker/lib/maintenance.sh')))
        with tempfile.TemporaryDirectory(prefix='.session-test-',dir=ROOT) as selected:
            commands='check-updates\n9router\nprintf "SHELL_PWD=%s\\n" "$PWD"\nexit\n'
            for action in ('terminal','claude'):
                result=subprocess.run(['/bin/bash',str(script),action,selected],env=self.env,input=commands,capture_output=True,text=True,timeout=10)
                self.assertIn('CHECK_ALIAS',result.stdout)
                self.assertIn('ROUTER_WRAPPER',result.stdout)
                self.assertIn('STATUS_LINE',result.stdout)
                self.assertIn('SHELL_PWD='+str(ROOT if action=='terminal' else selected),result.stdout)

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
