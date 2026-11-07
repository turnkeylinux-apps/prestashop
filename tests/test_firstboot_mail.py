"""Exercise firstboot marker lifecycle; actual vendor generation is checked in QA."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

HOOK = Path(__file__).resolve().parents[1] / 'overlay/usr/lib/inithooks/bin/prestashop.py'


class FirstbootMailTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.marker = Path(self.directory.name) / 'mail-needs-domain'
        self.marker.touch()
        self.generated = []
        modules = {
            'libinithooks': types.SimpleNamespace(inithooks_cache=types.SimpleNamespace(write=lambda *args: None)),
            'libinithooks.dialog_wrapper': types.SimpleNamespace(Dialog=lambda *args: self.fail('Unexpected prompt')),
            'mysqlconf': types.SimpleNamespace(MySQL=lambda: types.SimpleNamespace(execute=lambda *args: None)),
        }
        with patch.dict(sys.modules, modules):
            spec = importlib.util.spec_from_file_location('firstboot_prestashop', HOOK)
            self.hook = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.hook)
        self.addCleanup(patch.stopall)
        patch.object(self.hook, 'Path', return_value=self.marker).start()
        patch.object(self.hook.subprocess, 'run', side_effect=self.run_command).start()

    def run_command(self, command, **kwargs):
        if 'prestashop:mail:generate' in command:
            self.generated.append(command)
        return subprocess.CompletedProcess(command, 0, stdout=b'password hash')

    def setup_domain(self, domain):
        with patch.object(sys, 'argv', [str(HOOK), '--pass=disposable-password', '--email=owner@example.org', '--domain=' + domain]):
            self.hook.main()

    def test_default_fallback_defers_until_real_domain_then_preserves_customization(self):
        self.setup_domain('DEFAULT')
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.generated, [])
        self.setup_domain('shop.example.org')
        self.assertFalse(self.marker.exists())
        self.assertEqual(len(self.generated), 1)
        self.setup_domain('shop.example.org')
        self.assertEqual(len(self.generated), 1)

    def test_literal_factory_hostname_keeps_marker_and_skips_generation(self):
        self.setup_domain('www.example.com')
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.generated, [])

    def test_failed_real_domain_generation_keeps_marker_for_supported_retry(self):
        def fail_generation(command, **kwargs):
            if 'prestashop:mail:generate' in command:
                raise subprocess.CalledProcessError(1, command)
            return subprocess.CompletedProcess(command, 0, stdout=b'password hash')
        with patch.object(self.hook.subprocess, 'run', side_effect=fail_generation):
            with self.assertRaises(subprocess.CalledProcessError):
                self.setup_domain('shop.example.org')
        self.assertTrue(self.marker.exists())


if __name__ == '__main__':
    unittest.main()
