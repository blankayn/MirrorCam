# Build MirrorCam from Windows without owning a Mac

The included GitHub Actions workflow uses a GitHub-hosted macOS machine with Xcode 15.4 to build an unsigned iPhone IPA. You download the IPA to Windows, then Sideloadly signs and installs it. Your phone is needed only at the installation stage. The [first cloud build succeeded](https://github.com/blankayn/MirrorCam/actions/runs/37889696067) on 9 October 2026. [Download its IPA artifact](https://github.com/blankayn/MirrorCam/actions/runs/37889696067/artifacts/11597787130) and extract the ZIP. It expires on 16 October 2026; rerun the workflow when needed. Installation and physical-device tests are still pending.

## Availability and cost

Checked 9 October 2026: GitHub's [macOS 14 arm64 software list](https://github.com/actions/runner-images/blob/main/images/macos/macos-14-arm64-Readme.md) includes Xcode 15.4, and its [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) lists `macos-14`. **This runner retires on 2 November 2026**, with scheduled temporary outages before then. See the [retirement notice](https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/). During a scheduled outage, retry after it ends. After retirement, you will need another macOS build host that offers Xcode 14/15; changing to macos-latest alone will not provide the required toolchain.

Standard GitHub-hosted runners are free for public repositories. Private repositories use the account's included allowance and can incur charges beyond it. Public repositories make your source visible to others; choose visibility yourself. GitHub documents these conditions in its [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). This workflow starts when project files are pushed to main, or when you manually press Run workflow, and requires no Apple signing certificate or Apple ID secret on GitHub.

## Steps from Windows

1. Sign in to GitHub or create an account. Create an empty repository named `MirrorCam`. Choose its visibility, and initialize it with a README so it has a default branch.
2. Extract `MirrorCam-source.zip`. Open the extracted **MirrorCam** folder (the one containing `MirrorCam.xcodeproj`, `scripts`, and `.github`).
3. In the repository on GitHub choose **Add file → Upload files**. Drag the **contents** of that extracted folder into the upload area, including `.github`. Do not upload the ZIP itself or the `build` directory. Commit the upload to the default branch.
4. Confirm the repository contains `.github/workflows/build-ios.yml` at its root. If that file was missed by browser upload, use Add file → Create new file, enter that exact path, and paste the included workflow's contents. The local workspace also has the same workflow at its Git root if you prefer pushing the existing repository with Git.
5. Open **Actions → Build MirrorCam IPA**. A push to main starts a build automatically. To start another build manually, press **Run workflow**, select the default branch, and run it. If GitHub asks you to enable Actions for the repository, enable it first.
6. Wait for a successful run. Open the run's summary and download the **MirrorCam-unsigned-ipa** artifact. Extract the artifact ZIP on Windows to obtain `MirrorCam-unsigned.ipa`.
7. Connect your iPhone 6 by USB, trust the PC, and install the IPA with Sideloadly using the installation steps in `README.md`.

Expected standalone repository layout:

```text
.github/workflows/build-ios.yml
MirrorCam.xcodeproj/project.pbxproj
MirrorCam/AppDelegate.swift
MirrorCam/Info.plist
scripts/build-ipa.sh
scripts/validate-project.py
```

The workflow also supports the project's existing layout under a `MirrorCam/` subdirectory, provided the workflow is at the repository root. Both layouts are handled by its Locate project step.

## If the run fails

Open the failed step and read its error. Download **MirrorCam-build-log** when available and bring the compiler error back to this chat. A failed run does not produce a usable IPA. Source syntax checks do not replace this actual Xcode build, and a successful build still needs the physical-device checks in `DEVICE-TESTS.md`.

Do not upload Apple passwords or signing keys into source files. This unsigned cloud build has no use for them; enter your Apple ID into Sideloadly on your Windows PC when installing.
