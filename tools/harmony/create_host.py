#!/usr/bin/env python3
"""Render the upstream Flutter-OH host template without changing shared app code."""
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SDK=Path(os.environ.get('FLUTTER_OHOS_HOME',Path.home()/'Library/Developer/AcquireEnglish/flutter-ohos'))
SOURCE=SDK/'packages/flutter_tools/templates/app/ohos.tmpl'
TARGET=ROOT/'apps/mobile_harmony/ohos'

def create():
    if TARGET.exists():
        raise RuntimeError('Host already exists; refusing to overwrite local signing configuration')
    if not SOURCE.is_dir():raise RuntimeError('Flutter-OH templates are not installed')
    for source in SOURCE.rglob('*'):
        if not source.is_file() or 'ohosTest' in source.parts:continue
        relative=source.relative_to(SOURCE)
        target=TARGET/str(relative).removesuffix('.tmpl')
        target.parent.mkdir(parents=True,exist_ok=True)
        if source.name.endswith('.tmpl'):
            text=source.read_text().replace('{{projectName}}','爱快英语').replace('{{ohosIdentifier}}','com.acquire.english')
            if '{{' in text:raise RuntimeError(f'Unresolved template fields: {relative}')
            target.write_text(text)
        else:shutil.copyfile(source,target)
    # Package names must be ASCII; human-visible resource labels remain Chinese.
    package=TARGET/'oh-package.json5'
    package.write_text(package.read_text().replace('爱快英语','acquire_english_harmony'))
    profile=TARGET/'build-profile.json5'
    profile.write_text(profile.read_text().replace('        "signingConfig": "default",\n',''))
    # Mirror mobile version; signing remains a local DevEco configuration.
    match=re.search(r'^version:\s*([^+\s]+)\+(\d+)',(ROOT/'apps/mobile/pubspec.yaml').read_text(),re.M)
    app=TARGET/'AppScope/app.json5'
    data=json.loads(app.read_text());data['app'].update(vendor='AcquireEnglish',versionName=match[1],versionCode=int(match[2]))
    app.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    icon=ROOT/'apps/mobile/assets/img/app_icon.png'
    for location in ['AppScope/resources/base/media/app_icon.png','entry/src/main/resources/base/media/icon.png']:
        shutil.copyfile(icon,TARGET/location)
    module=TARGET/'entry/src/main/module.json5'
    text=module.read_text().replace('{"name" :  "ohos.permission.INTERNET"},','''{"name": "ohos.permission.INTERNET"},
      {"name": "ohos.permission.MICROPHONE", "reason": "$string:microphone_reason", "usedScene": {"abilities": ["EntryAbility"], "when": "inuse"}},
      {"name": "ohos.permission.CAMERA", "reason": "$string:camera_reason", "usedScene": {"abilities": ["EntryAbility"], "when": "inuse"}},''')
    module.write_text(text)
    for locale in ['base','zh_CN','en_US']:
        path=TARGET/f'entry/src/main/resources/{locale}/element/string.json'
        data=json.loads(path.read_text())
        data['string'] += [
            {'name':'microphone_reason','value':'用于口语练习录音和语音对话' if locale!='en_US' else 'Record speaking exercises and voice conversations'},
            {'name':'camera_reason','value':'用于拍照导入学习材料' if locale!='en_US' else 'Photograph learning materials for import'}]
        path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print('Created Harmony FlutterAbility host; certificates and signing profile still required')

if __name__=='__main__':create()
