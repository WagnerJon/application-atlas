# Maintainer release guide

No Apple Developer account, signing certificate, or custom GitHub secret is required. Builds use an ad-hoc signature and are not notarized.

## Repository setup

The intended repository is **WagnerJon/application-atlas**. Create an empty public GitHub repository (do not initialize its README or license), then push this project's source to its main branch. The repository includes the MIT license and `.github/FUNDING.yml` for the Buy Me a Coffee Sponsor button. Ensure **Settings → General → Features → Sponsorships** and GitHub Actions are enabled.

Do not upload `build/`, `dist/`, personal databases, documents, exports, or backups to source control. Compiled binaries belong in Releases.

## Release a version

1. Update `VERSION` (numeric `X.Y.Z`) and `docs/RELEASE-NOTES.md`. Run `./scripts/test.sh` and `./scripts/release.sh` on macOS.
2. Test the app, including a fresh launch, editing steps/categories, attachments, and backup/restore. Before calling compatibility verified, test on macOS 14 and a second Mac. Hosted tests run on macOS 15 on both architectures; they do not validate UI or downloaded-app Gatekeeper behavior.
3. Commit and push the changes. Tag that commit, for example:

   ```sh
   git tag -a v1.0.0 -m "Application Atlas 1.0.0"
   git push origin v1.0.0
   ```

4. The workflow tests on Apple Silicon and Intel, verifies the tag matches `VERSION`, builds a universal app, and publishes a **GitHub Release** with the ZIP, SHA-256 checksum, license, and installation guide. The workflow uses GitHub's short-lived built-in token with write access only in the release job.
5. Download and verify the published ZIP. Version tags publish automatically after both test jobs pass, so complete local review before pushing a tag. If a release already exists, inspect it rather than recreating the tag or overwriting a published release.

PRs and branch pushes test and build without publishing. For local packaging use `./scripts/release.sh`; output is in `dist/`. The bundle identifier stays `local.applicationatlas.mac` to preserve continuity with existing builds. Storage is independent of the identifier. Version information in About comes from the app bundle.
