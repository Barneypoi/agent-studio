#!/usr/bin/env python3
"""Build the Apple Silicon .app from a local Godot editor and Node runtime."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import struct

p=argparse.ArgumentParser()
p.add_argument('--godot',required=True,type=pathlib.Path)
p.add_argument('--node',required=True,type=pathlib.Path)
p.add_argument('--output',type=pathlib.Path)
a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent.parent
app=(a.output or root.parent/'栖点工作室.app').resolve()
godot=a.godot.resolve();node=a.node.resolve()
if app.exists():raise SystemExit('Output already exists; choose a new output path.')
mac=app/'Contents/MacOS';resources=app/'Contents/Resources'
mac.mkdir(parents=True);(resources/'runtime').mkdir(parents=True)
def run(*cmd):subprocess.run([str(x) for x in cmd],check=True)
run('xcrun','clang','-O2','-Wall','-Wextra','-arch','arm64',root/'tools/launcher.c','-o',mac/'AgentStudio')
run('xcrun','lipo',godot,'-thin','arm64','-output',mac/'GodotEngine')
shutil.copy2(node,resources/'runtime/node')
shutil.copytree(root/'bridge',resources/'bridge',ignore=shutil.ignore_patterns('tests'))
shutil.copytree(root/'sample-project',resources/'sample-project')
(resources/'licenses').mkdir()
for f in [root/'docs/GODOT-LICENSE.txt',root/'docs/GODOT-COPYRIGHT.txt',root/'docs/NODE-LICENSE.txt',root/'game/assets/FONT-LICENSE.txt']:
    shutil.copy2(f,resources/'licenses'/f.name)
# Pack export does not require Godot export templates; use the bundled engine.
run(godot,'--headless','--path',root/'game','--export-pack','macOS',resources/'game.pck','--log-file',resources/'export.log')
plist={
    'CFBundleName':'栖点工作室','CFBundleDisplayName':'栖点工作室',
    'CFBundleExecutable':'AgentStudio','CFBundleIdentifier':'studio.qidian.agentstudio',
    'CFBundleVersion':'1.0.0','CFBundleShortVersionString':'1.0.0',
    'CFBundlePackageType':'APPL','LSMinimumSystemVersion':'12.0',
    'NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication',
    'NSLocalNetworkUsageDescription':'连接仅监听本机的 Codex 任务桥接。',
}
with (app/'Contents/Info.plist').open('wb') as f:plistlib.dump(plist,f)
with tempfile.TemporaryDirectory(prefix='agent-studio-icon-') as temp:
    temp=pathlib.Path(temp);script=temp/'icon.gd';png=temp/'icon.png';iconset=temp/'AppIcon.iconset';iconset.mkdir()
    script.write_text('extends SceneTree\nfunc _initialize():\n\tvar img=Image.new()\n\timg.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"),4.0)\n\timg.save_png(OS.get_cmdline_user_args()[0])\n\tquit()\n')
    run(godot,'--headless','--path',root/'game','--script',script,'--log-file',temp/'icon.log','--',png)
    for size in [16,32,128,256,512]:
        for scale in [1,2]:run('sips','-z',size*scale,size*scale,png,'--out',iconset/f'icon_{size}x{size}{"@2x" if scale==2 else ""}.png')
    chunks=[]
    for size,kind in [(128,b'ic07'),(256,b'ic08'),(512,b'ic09'),(1024,b'ic10')]:
        name=f'icon_{size}x{size}.png' if size<1024 else 'icon_512x512@2x.png'
        png_bytes=(iconset/name).read_bytes();chunks.append(kind+struct.pack('>I',len(png_bytes)+8)+png_bytes)
    body=b''.join(chunks);(resources/'AppIcon.icns').write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
plist['CFBundleIconFile']='AppIcon.icns'
with (app/'Contents/Info.plist').open('wb') as f:plistlib.dump(plist,f)
for binary in [mac/'GodotEngine',resources/'runtime/node',mac/'AgentStudio']:
    run('codesign','--force','--sign','-',binary)
run('codesign','--force','--sign','-',app)
run('codesign','--verify','--deep','--strict',app)
print('BUILT',app)
