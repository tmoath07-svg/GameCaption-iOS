#!/usr/bin/env python3
"""Basic license/hygiene/packaging checks, not a substitute for Xcode compilation."""
from pathlib import Path
import plistlib, sys, zipfile
root=Path(__file__).resolve().parent.parent
code=list((root/'GameCaption').glob('*.swift'))
assert len(code)>=6, 'missing source modules'
required=['ContentView.swift','OCRService.swift','GameCaptionApp.swift',
          'LiveCameraScanner.swift','LiveSpeechRecognizer.swift','LocalCaptionServer.swift','CaptionStore.swift']
for name in required: assert (root/'GameCaption'/name).is_file(),f'missing {name}'
for file in code:
    data=file.read_text()
    assert 'com.guleryuz' not in data, f'unexpected reference app bundle id in {file}'
    assert 'SherpaOnnxC' not in data, f'reference app framework in {file}'
assert not list(root.rglob('*.onnx')), 'reference-model weights included'
assert not list(root.rglob('GameDictionaries.bin')), 'reference dictionary included'
assert (root/'GameCaption/Assets.xcassets/AppIcon.appiconset/icon-1024.png').is_file()
print('PASS: independent source hygiene, file inventory and icon present')
if len(sys.argv)==2:
    ipa=Path(sys.argv[1]); assert ipa.is_file(), 'IPA missing'
    with zipfile.ZipFile(ipa) as z:
        invalid=z.testzip(); assert invalid is None, f'broken archive member: {invalid}'
        app='Payload/GameCaption.app/'
        entries=z.namelist()
        assert app+'Info.plist' in entries, 'Info.plist not found'
        info=plistlib.loads(z.read(app+'Info.plist'))
        assert info.get('CFBundleIdentifier')=='com.tmoath07.gamecaption', info.get('CFBundleIdentifier')
        assert info.get('CFBundleShortVersionString')=='0.2.0', 'wrong version'
        assert info.get('UIDeviceFamily')==[1], 'app is not iPhone only'
        assert any(p.startswith(app) and p.endswith('/GameCaption') for p in entries) or app+'GameCaption' in entries, 'executable missing'
    print(f'PASS: {ipa.name}, file integrity, version and iPhone-only configuration')
