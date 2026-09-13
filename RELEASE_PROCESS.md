# Release process

## Git Flow

- `main` contains released versions; `develop` contains integrated work for the next release.
- Start features from `develop` under `feature/…` and merge them back when checked.
- Start `release/X.Y.Z` from `develop`. Update `Config/release.json`, release notes, and checks.
- Finish by merging the release into `main` with a merge commit, tag `vX.Y.Z`, then merge `main` back into `develop`.
- Start urgent `hotfix/X.Y.Z` from `main`; merge completed fixes into both `main` and `develop` and tag them.
- Git Flow branch/prefix settings are configured locally. Standard Git commands implement this flow; the separate git-flow extension is not required.

## Signed updates

`Config/release.json` is the single source of version, monotonically increasing build number, public update key, feed address and repository. Do not change the bundle identifier for updates. Keep the private signing key in the login Keychain under the configured account. It must never enter the repository, release artifacts or CI logs. Back it up securely before moving development to another Mac.

The update feed is the `appcast.xml` asset of the latest GitHub Release. Every release must include the app archive and the freshly generated appcast together. The feed points to that release's immutable version-specific archive URL. Publish as a draft first, upload and validate every artifact, and only then mark the release public. Increment the build number for every distributed build. Do not overwrite an already published application archive.

Run `bash scripts/build.sh`, `bash scripts/check.sh`, then `python3 scripts/package-release.py`. The packaging script uses Sparkle's signing tools, generates the feed, and produces checksums. Verify the update using a disposable older app copy before publication. Use `gh release create` with `--draft`, `--verify-tag` and `--notes-file RELEASE_NOTES.md`, attach every artifact, then publish the draft.

The initial 1.0 release uses ad-hoc signing because no Developer ID Application certificate is available on the release Mac. Future Developer ID signing/notarization must sign Sparkle's nested helpers correctly and preserve the existing Sparkle key. Do not describe the current download as notarized.

Source license has not been chosen. No open-source license is granted by publication alone. Sparkle's license is included in the bundled framework and in THIRD_PARTY_NOTICES.md.

## Repeat the update integration test

Run `python3 scripts/build-update-test-driver.py` after resolving/building the app. It fetches the official Sparkle 2.9.6 command-line driver sources with pinned SHA-256 checksums and links the already verified framework. Then run `python3 scripts/test-update.py` with normal macOS service and Keychain access. The test starts a loopback-only HTTP server, creates two disposable bundles with a separate identifier, discovers and installs the signed update, verifies the installed build, checks the no-update state, and tests rejection of a modified archive. The real app is never launched or replaced by this test. The test-only HTTP exception is not included in release bundles.
