#!/usr/bin/env python3
"""Build the native Apple Silicon app; runtime/account state stays in Application Support."""
from pathlib import Path
import plistlib,subprocess,sys
source=Path(__file__).resolve().parent
destination=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()/'build-native'
destination.mkdir(parents=True,exist_ok=True)
app=destination/'EVA Workbench.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
(app/'Contents/Resources').mkdir(exist_ok=True)
# Boot sequence media from the web workbench: Mincho subset (OFL), authorised Japanese announcement and its cue timeline.
import shutil
public=source.parent/'workbench'/'public'
for src,name in [(public/'fonts'/'unit02-mincho-black.woff2','unit02-mincho-black.woff2'),(public/'fonts'/'OFL-NotoSerifCJK.txt','OFL-NotoSerifCJK.txt'),(public/'media'/'audio-unit02-fluid'/'voice.wav','intro-voice.wav'),(public/'media'/'audio-unit02-fluid'/'timeline.json','intro-timeline.json'),(public/'media'/'audio-unit02-fluid'/'README.md','intro-voice-README.md')]:
 shutil.copyfile(src,app/'Contents/Resources'/name)
swift_files=['NativeCore.swift','NativeUI.swift','NativeActions.swift','NativeTools.swift','NativePreferences.swift','NativeAttachments.swift','NativeIntro.swift','NativeStyle.swift','NativeMarkdown.swift','EVAWorkbench.swift']
subprocess.run(['swiftc','-parse-as-library','-O','-target','arm64-apple-macos13.3','-framework','AppKit','-framework','UniformTypeIdentifiers','-framework','PDFKit','-framework','AVFoundation','-framework','CoreImage',*[str(source/name) for name in swift_files],'-o',str(app/'Contents/MacOS/eva-workbench')],check=True)
subprocess.run([str(app/'Contents/MacOS/eva-workbench'),'--self-test'],check=True)
icon=destination/'AppIcon.png';iconset=destination/'AppIcon.iconset';iconset.mkdir(exist_ok=True)
subprocess.run(['swift',str(source/'make-icon.swift'),str(icon)],check=True)
for size in [16,32,128,256,512]:
 for scale in [1,2]:
  name='icon_'+str(size)+'x'+str(size)+('@2x' if scale==2 else '')+'.png'
  subprocess.run(['sips','-z',str(size*scale),str(size*scale),str(icon),'--out',str(iconset/name)],capture_output=True,check=True)
subprocess.run(['iconutil','-c','icns',str(iconset),'-o',str(app/'Contents/Resources/AppIcon.icns')],check=True)
info={'CFBundleName':'EVA Workbench','CFBundleDisplayName':'EVA Workbench','CFBundleIdentifier':'local.eva.dual-workbench','CFBundleExecutable':'eva-workbench','CFBundleIconFile':'AppIcon','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.10.2','CFBundleVersion':'0.10.2','LSMinimumSystemVersion':'13.3','LSApplicationCategoryType':'public.app-category.developer-tools','NSHighResolutionCapable':True,'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'NSHumanReadableCopyright':'Native Swift/AppKit EVA Workbench. Based on EVA Codex Workbench (MIT).'}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
# Generated graphics can inherit Finder metadata in Documents; it is not code-signable.
for attribute in ('com.apple.FinderInfo','com.apple.ResourceFork'):
 subprocess.run(['/usr/bin/xattr','-r','-d',attribute,str(app)],capture_output=True)
subprocess.run(['codesign','--force','--sign','-','--identifier','local.eva.dual-workbench',str(app)],check=True)
for attribute in ('com.apple.FinderInfo','com.apple.ResourceFork'):
 subprocess.run(['/usr/bin/xattr','-r','-d',attribute,str(app)],capture_output=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)
