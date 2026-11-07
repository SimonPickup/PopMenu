#!/usr/bin/env python3
"""Run complete PopMenu sources against real host Catalyst UIKit, no simulator.
No application, native window or scene is launched. Layout callbacks are explicit;
nonzero safe-area insets are supplied by the labelled UIKit fixture in main.swift.
"""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vendor', type=Path, default=ROOT / 'PopMenu')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('Real UIKit tests require a Mac/Xcode host; this is not a passing skip')
    sources = sorted(args.vendor.resolve().rglob('*.swift'))
    assert len(sources) == 10, 'Expected complete pinned 10-file PopMenu Swift tree'
    controller = next(p for p in sources if p.name == 'PopMenuViewController.swift')
    shim = '''
// Test-only access to production setup, without changing method bodies.
extension PopMenuViewController {
    func harnessInstallRoot(_ root: UIView) {
        view = root
        view.backgroundColor = .clear
        configureBackgroundView()
        configureContentView()
        configureActionsView()
    }
}
'''
    ios_sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    # Verify the existing CocoaPods/Xcode minimum in both supported language modes.
    for language in ['4.2', '5']:
        print('Typechecking iOS 10.0 / Swift ' + language, flush=True)
        subprocess.run(['xcrun', 'swiftc', '-typecheck', '-swift-version', language,
                        '-target', 'arm64-apple-ios10.0', '-sdk', ios_sdk,
                        *map(str, sources)], check=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    arch = platform.machine()
    assert arch in ('arm64', 'x86_64'), arch
    with tempfile.TemporaryDirectory(prefix='pop-menu-uikit-', dir=os.environ.get('TMPDIR')) as tmp:
        scratch = Path(tmp)
        generated = scratch / 'PopMenuViewController+Harness.swift'
        generated.write_text(controller.read_text() + shim)
        inputs = [generated if path == controller else path for path in sources]
        command = ['xcrun', 'swiftc', '-swift-version', '5', '-target', arch + '-apple-ios15.0-macabi',
                   '-sdk', sdk, '-F', sdk + '/System/iOSSupport/System/Library/Frameworks',
                   '-I', sdk + '/System/iOSSupport/usr/include', '-L', sdk + '/System/iOSSupport/usr/lib',
                   *map(str, inputs), str(ROOT / 'Tests/WindowLayout/main.swift'),
                   '-o', str(scratch / 'popmenu-tests.bin')]
        print('Compiling all production PopMenu Swift files against real Catalyst UIKit', flush=True)
        subprocess.run(command, check=True)
        subprocess.run([str(scratch / 'popmenu-tests.bin')], check=True)


if __name__ == '__main__':
    main()
