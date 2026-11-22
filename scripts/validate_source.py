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
voice_dir = root / 'GameCaption' / 'NeuralArabicVoice'
unexpected_models = [p for p in (root / 'GameCaption').rglob('*.onnx') if p.parent != voice_dir]
assert not unexpected_models, f'unlicensed/unexpected model weights: {unexpected_models}'

assert not list(root.rglob('GameDictionaries.bin')), 'reference dictionary included'
assert (root/'GameCaption/Assets.xcassets/AppIcon.appiconset/icon-1024.png').is_file()
assert (root/'GameCaptionBroadcast/SampleHandler.swift').is_file(), 'ReplayKit broadcast handler missing'
for entitlement in ('GameCaption/GameCaption.entitlements', 'GameCaptionBroadcast/GameCaptionBroadcast.entitlements'):
    with (root / entitlement).open('rb') as f:
        ent = plistlib.load(f)
    assert 'group.com.tmoath07.gamecaption' in ent.get('com.apple.security.application-groups', []), entitlement
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
        assert info.get('CFBundleShortVersionString')=='0.4.0', 'wrong version'
        assert info.get('UIDeviceFamily')==[1], 'app is not iPhone only'
        assert any(p.startswith(app) and p.endswith('/GameCaption') for p in entries) or app+'GameCaption' in entries, 'executable missing'
        ext=app+'PlugIns/GameCaptionBroadcast.appex/'
        assert ext+'Info.plist' in entries, 'embedded ReplayKit extension missing'
        assert ext+'GameCaptionBroadcast' in entries, 'ReplayKit executable missing'
        extinfo=plistlib.loads(z.read(ext+'Info.plist'))
        assert extinfo['NSExtension']['NSExtensionPointIdentifier']=='com.apple.broadcast-services-upload', 'wrong ReplayKit extension point'
        voice = app + 'NeuralArabicVoice/'
        for filename, minimum in [('model.int8.onnx', 50_000_000),
                                  ('model.fp16.onnx', 120_000_000),
                                  ('voices.bin', 100_000),
                                  ('tokens.txt', 200)]:
            path = voice + filename
            assert path in entries, f'voice pack missing: {filename}'
            assert z.getinfo(path).file_size > minimum, f'voice asset too small: {filename}'
        assert voice + 'espeak-ng-data/phontab' in entries, 'phonemization tables missing'
        assert extinfo['NSExtension']['NSExtensionAttributes']['RPBroadcastProcessMode']=='RPBroadcastProcessModeSampleBuffer', 'missing sample buffer mode'
    print(f'PASS: {ipa.name}, file integrity, version and iPhone-only configuration')
