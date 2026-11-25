#!/usr/bin/env python3
"""Create the isolated Harmony dependency profile from the shared mobile app."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'apps/mobile'
TARGET = ROOT / 'apps/mobile_harmony'

def prepare():
    TARGET.mkdir(parents=True, exist_ok=True)
    manifest=json.loads((Path(__file__).parent/'plugins.json').read_text())
    text=(SOURCE/'pubspec.yaml').read_text()
    if re.search(r'^dependency_overrides:', text, re.M):
        raise RuntimeError('Main profile now contains overrides; merge them explicitly first')
    for name in manifest.get('excluded_dev_dependencies', []):
        text, count = re.subn(rf'^  {re.escape(name)}:[^\n]*\n', '', text, flags=re.M)
        if count != 1:
            raise RuntimeError(f'Expected one single-line dev dependency: {name}')
    text+='\n# Harmony-only plugin implementations; Android/iOS keep the original profile.\ndependency_overrides:\n'
    for name, version in manifest.get('compatibility_overrides', {}).items():
        text += f'  {name}: {version}\n'
    for name,spec in manifest['overrides'].items():
        text+=f'  {name}:\n    git:\n      url: {spec["url"]}\n      ref: {spec["ref"]}\n'
        if 'path' in spec:text+=f'      path: {spec["path"]}\n'
    (TARGET/'pubspec.yaml').write_text(text)
    for name in ['lib','assets','third_party']:
        link=TARGET/name
        if link.is_symlink():
            if link.readlink()!=Path('../mobile')/name:raise RuntimeError(f'Unexpected link: {name}')
        elif link.exists():
            raise RuntimeError(f'Refusing to replace existing {name}')
        else:link.symlink_to(Path('../mobile')/name,target_is_directory=True)
    (TARGET/'analysis_options.yaml').write_text('include: ../mobile/analysis_options.yaml\n')
    print('Prepared Harmony profile sharing lib/assets with mobile; original pubspec untouched')

if __name__=='__main__':prepare()
