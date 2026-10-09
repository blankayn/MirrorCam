# Validation record

Date: 9 October 2026 (Asia/Manila). Local environment: Windows, Python 3.11. Cloud build: GitHub-hosted macOS, Xcode 15.4.

Executed successfully:

- `python scripts/generate-icons.py`: generated eight opaque RGB PNG app icons; inspected the rendered icon visually.
- `python scripts/validate-project.py`: **100 structural/syntax checks passed across eight Swift source files** using tree-sitter 0.25.2 / tree-sitter-swift 0.7.4.
- `bash -n scripts/build-ipa.sh`: Bash script parses successfully using the installed Git Bash.

The validator parses the OpenStep project, resolves object references and source-phase membership, checks all deployment configurations, parses plist/storyboard/scheme XML, verifies privacy descriptions, and checks icon pixel dimensions. Swift parsing detects syntax errors only. It does not resolve Apple framework types, validate API availability, compile code, or exercise camera/PhotoKit behavior.

The [GitHub Actions run 37889696067](https://github.com/blankayn/MirrorCam/actions/runs/37889696067) successfully compiled the Release iOS app with Xcode 15.4 at commit `b6a3bb491de26685edca5c56537b6644d61093b4`. The log reports `BUILD SUCCEEDED`, a minimum OS version of `12.0`, and an `arm64` app executable. The build script packaged an unsigned IPA, including the embedded Swift compatibility libraries. The downloaded artifact ZIP matched GitHub's SHA-256 digest: `8f51304e5767b0637fc92e1eaabffe6721ebae081e84fa72ae3e6f0248644bb8`.

**Not performed:** code signing, installation, simulator execution, or any physical iPhone test. Hardware encoder behavior, camera format selection, photo mirroring metadata, audio sync, rolling-buffer timing and interruption recovery require the physical-device checklist in `DEVICE-TESTS.md`. A successful compilation does not establish these runtime behaviors.
