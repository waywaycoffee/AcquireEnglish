#!/usr/bin/env python3
"""Validate the Harmony host contract, optionally require the build toolchain."""
import argparse
import json
import os
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
TARGET=ROOT/'apps/mobile_harmony'

def read_json5(path):
    text=re.sub(r'^\s*//.*$', '',path.read_text(),flags=re.M)
    return json.loads(re.sub(r',\s*([}\]])', r'\1',text))

def check(require_toolchain=False):
    errors=[]
    host=TARGET/'ohos'
    app=read_json5(host/'AppScope/app.json5')['app']
    if app['bundleName']!='com.acquire.english':errors.append('Unexpected bundle name')
    version=re.search(r'^version:\s*([^+\s]+)\+(\d+)',(ROOT/'apps/mobile/pubspec.yaml').read_text(),re.M)
    if (app['versionName'],app['versionCode'])!=(version[1],int(version[2])):errors.append('Host version differs from mobile version')
    for name in ['lib','assets','third_party']:
        if not (TARGET/name).is_symlink() or (TARGET/name).resolve()!=(ROOT/'apps/mobile'/name).resolve():errors.append(f'{name} is not shared with mobile')
    module=read_json5(host/'entry/src/main/module.json5')['module']
    permissions=module['requestPermissions']
    if not {'ohos.permission.INTERNET','ohos.permission.MICROPHONE','ohos.permission.CAMERA'} <= {p['name'] for p in permissions}:errors.append('Missing core permissions')
    for p in permissions:
        if p['name']!='ohos.permission.INTERNET' and (not p.get('reason') or p.get('usedScene',{}).get('when')!='inuse'):errors.append('Sensitive permission lacks in-use explanation')
    for file in host.rglob('*.json'):
        try:read_json5(file)
        except ValueError:errors.append(f'Invalid JSON: {file.relative_to(host)}')
    for file in host.rglob('*'):
        if file.is_file() and file.suffix.lower() in {'.mp3','.wav','.mp4','.m4a','.ogg','.aac'}:errors.append('Bundled audio/video is prohibited')
    manifest=json.loads((ROOT/'tools/harmony/plugins.json').read_text())
    for name,spec in manifest['overrides'].items():
        if not re.fullmatch('[0-9a-f]{40}',spec['ref']):errors.append(f'Unpinned plugin: {name}')
    sdk=Path(os.environ.get('FLUTTER_OHOS_HOME',Path.home()/'Library/Developer/AcquireEnglish/flutter-ohos'))
    deveco=Path(os.environ.get('DEVECO_HOME','/Applications/DevEco-Studio.app/Contents'))
    if require_toolchain:
        if not (deveco/'sdk').is_dir():errors.append('DevEco Studio / HarmonyOS SDK is not installed')
        if not (sdk/'bin/cache/dart-sdk/bin/dart').is_file():errors.append('Flutter-OH Dart SDK bootstrap is incomplete')
        r=subprocess.run(['git','-C',str(sdk),'rev-parse','HEAD'],capture_output=True,text=True)
        if r.stdout.strip()!=manifest['sdk']['ref']:errors.append('Flutter-OH SDK checkout does not match pinned release')
    for error in errors:print('FAIL:',error)
    if not errors:print('Harmony host configuration checks passed'+(' with toolchain' if require_toolchain else '; native compilation still requires installed SDKs'))
    return int(bool(errors))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--require-toolchain',action='store_true')
    raise SystemExit(check(parser.parse_args().require_toolchain))
