#!/usr/bin/env python3
"""Basic license/hygiene/packaging checks, not a substitute for Xcode compilation."""
from pathlib import Path
import plistlib, re, struct, sys, zipfile
root=Path(__file__).resolve().parent.parent
code = [file for folder in ('GameCaption', 'GameCaptionBroadcast', 'Shared')
        for file in (root / folder).glob('*.swift')]
project = (root / 'project.yml').read_text()
versions = re.findall(r"^ +MARKETING_VERSION: '([0-9.]+)'$", project, re.M)
assert len(versions) == 2 and versions[0] == versions[1], 'app and extension marketing versions differ'
version = versions[0]
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
    assert f'CODE_SIGN_ENTITLEMENTS: {entitlement}' in project, entitlement
    with (root / entitlement).open('rb') as f:
        ent = plistlib.load(f)
    assert ent.get('com.apple.security.application-groups') == ['group.com.tmoath07.gamecaption'], entitlement
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
        assert info.get('CFBundleShortVersionString') == version, 'wrong version'
        assert ipa.name == f'GameCaption-{version}-unsigned.ipa', 'wrong filename'
        assert app+'Assets.car' in entries, 'compiled asset catalog missing'
        assert info.get('UIDeviceFamily')==[1], 'app is not iPhone only'
        ext=app+'PlugIns/GameCaptionBroadcast.appex/'
        assert ext+'Info.plist' in entries, 'embedded ReplayKit extension missing'
        extinfo=plistlib.loads(z.read(ext+'Info.plist'))
        assert extinfo['CFBundleIdentifier'] == 'com.tmoath07.gamecaption.BroadcastExtension'
        assert extinfo['CFBundleShortVersionString'] == version
        assert extinfo['CFBundleVersion'] == info['CFBundleVersion']
        assert extinfo['UIDeviceFamily'] == [1]
        assert extinfo['NSExtension']['NSExtensionPrincipalClass'] == 'GameCaptionBroadcast.SampleHandler'
        for path, metadata in ((app, info), (ext, extinfo)):
            assert path + 'embedded.mobileprovision' not in entries, 'unexpected provisioning profile'
            assert path + '_CodeSignature/CodeResources' not in entries, 'unexpected signature'
            assert metadata['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'device build required'
            with z.open(path + metadata['CFBundleExecutable']) as executable:
                magic, cpu = struct.unpack('<II', executable.read(8))
                assert magic == 0xfeedfacf and cpu == 0x0100000c, 'arm64 Mach-O required'
        assert extinfo['NSExtension']['NSExtensionPointIdentifier']=='com.apple.broadcast-services-upload', 'wrong ReplayKit extension point'
        assert not any(name.endswith(('.onnx', '/voices.bin')) or '/espeak-ng-data/' in name
                       for name in entries), 'optional neural assets in public IPA'
        assert extinfo['NSExtension']['NSExtensionAttributes']['RPBroadcastProcessMode']=='RPBroadcastProcessModeSampleBuffer', 'missing sample buffer mode'
    print(f'PASS: {ipa.name}, file integrity, version and iPhone-only configuration')
