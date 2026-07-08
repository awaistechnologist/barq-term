# Releasing Barq

Repo: **github.com/awaistechnologist/barq-term** (public). App name stays **Barq**.

## Cut a release

1. Bump the version and build the app + DMG:
   ```bash
   ./scripts/make-app.sh 0.7.1
   ./scripts/make-dmg.sh 0.7.1        # prints the DMG's sha256
   ```
2. Tag and push:
   ```bash
   git tag v0.7.1 && git push origin main --tags
   ```
3. Create the GitHub release for `v0.7.1` and upload `dist/Barq-0.7.1.dmg` as an asset.
   (Or `gh release create v0.7.1 dist/Barq-0.7.1.dmg --title "Barq 0.7.1" --notes-file CHANGELOG.md`.)

The in-app updater polls `releases/latest`, so once the release is published every
running copy shows a "Barq 0.7.1 is available → Download" banner.

## Homebrew tap (best unsigned install + `brew upgrade` updates)

One-time: create a public repo **homebrew-barq**, add `Casks/barq-term.rb`
(copy `packaging/barq-term.rb`). Each release, update the cask's `version` and
`sha256` (from `make-dmg.sh`) and push.

Users then:
```bash
brew tap awaistechnologist/barq
brew install --cask barq-term            # add --no-quarantine to skip the Gatekeeper prompt
brew upgrade --cask barq-term            # updates
```

## Gatekeeper (unsigned)

The app is ad-hoc signed, not notarized, so a browser-downloaded DMG is
quarantined and shows one Gatekeeper prompt. First launch:
**right-click Barq.app → Open**, or **System Settings → Privacy & Security →
Open Anyway**. Homebrew `--no-quarantine` avoids it. When you get an Apple
Developer ID, add `codesign --options runtime` + `xcrun notarytool submit` to
`make-app.sh` and this step disappears.
