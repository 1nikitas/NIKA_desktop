#!/usr/bin/env python3
"""Package the checksum-pinned macOS slice resolved by SwiftPM."""
from pathlib import Path
import shutil, subprocess, sys
root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1])
source = root / '.build/artifacts/webrtc/WebRTC/WebRTC.xcframework/macos-x86_64_arm64/WebRTC.framework'
if not source.exists():
    sys.exit('Resolved macOS WebRTC framework is missing; run swift package resolve.')
target = app / 'Contents/Frameworks/WebRTC.framework'
if target.exists(): shutil.rmtree(target)
shutil.copytree(source, target, symlinks=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True)
executable = app / 'Contents/MacOS/NIKADesktop'
subprocess.run(['install_name_tool', '-add_rpath', '@executable_path/../Frameworks', str(executable)], check=True)
license_target = app / 'Contents/Resources/RuntimeLicenses/WebRTC-LICENSE.md'
license_target.unlink(missing_ok=True)
shutil.copyfile(root / '.build/checkouts/WebRTC/LICENSE.md', license_target)
