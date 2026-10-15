# Releasing SimpleMapper

Releases are built, signed, notarized and published from your own Mac. There is no CI release workflow: the only GitHub workflow, `.github/workflows/deploy-pages.yml`, publishes `appcast.xml` to GitHub Pages so installed apps can find updates at `https://dinhanhthi.github.io/SimpleMapper/appcast.xml` (`SUFeedURL`).

Each release ships two notarized assets on the GitHub Release:

- `SimpleMapper-X.Y.Z.dmg`: drag-to-install download for new users.
- `SimpleMapper-X.Y.Z.zip`: the Sparkle update archive referenced by the appcast.

## §0 One-time setup

Never paste passwords, app-specific passwords or private keys into an AI chat. Run the commands below in your own terminal.

### Tools

- Xcode 26+ selected (`sudo xcode-select -s /Applications/Xcode.app`); older Xcode ships a blank app icon and the build script refuses it.
- XcodeGen: `brew install xcodegen`.
- GitHub CLI: `brew install gh`, then `gh auth login`.

### Apple Developer account and Developer ID certificate

- Paid Apple Developer account, Team ID `86H6CNLN4C` (see developer.apple.com/account > Membership details).
- Create a "Developer ID Application" certificate in Xcode > Settings > Accounts > select the team > Manage Certificates > + > Developer ID Application. It must be in the login Keychain.
- Verify:

  ```sh
  security find-identity -v -p codesigning
  ```

  The list must contain `Developer ID Application: ... (86H6CNLN4C)`.

### Notarization credentials

1. Create an app-specific password at account.apple.com > Sign-In and Security > App-Specific Passwords.
2. Store it in a notarytool Keychain profile (notarytool prompts for the app-specific password interactively, so it never lands in shell history or `ps`):

   ```sh
   xcrun notarytool store-credentials simplemapper-notary --apple-id <email> --team-id 86H6CNLN4C
   ```

To reuse an existing profile of the same team instead (for example one created for another app), point the scripts at it:

```sh
export SIMPLEMAPPER_NOTARY_PROFILE=<name>
```

Check the profile with `xcrun notarytool history --keychain-profile simplemapper-notary`.

### Sparkle EdDSA key

Sparkle only installs updates signed with the private key that matches `SUPublicEDKey` in the app. SimpleMapper uses its own Keychain account (`SimpleMapper`), so it never reuses another app's key stored under Sparkle's default account.

1. Build the app once in Debug (`scripts/dev.sh`) so Xcode downloads the Sparkle tools into DerivedData.
2. Generate the key pair (the private key goes into the login Keychain):

   ```sh
   ~/Library/Developer/Xcode/DerivedData/SimpleMapper-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account SimpleMapper
   ```

3. Paste the printed public key into `SUPublicEDKey` in `SimpleMapper/Info.plist` and commit it. The updater does not start, and `build-and-notarize.sh` refuses to build, while it is empty.
4. Back up the private key. Export it into a private temp dir under `umask 077` (never Desktop or Documents: they may sync to iCloud, and a file created before `chmod` is briefly world-readable), store the file's content in a password manager, then delete it:

   ```sh
   G=$(find ~/Library/Developer/Xcode/DerivedData/SimpleMapper-*/SourcePackages/artifacts -name generate_keys -type f 2>/dev/null | head -1)
   d=$(mktemp -d) && (umask 077 && "$G" --account SimpleMapper -x "$d/sparkle_private_key.txt")
   # copy the content of "$d/sparkle_private_key.txt" into your password manager, then:
   rm -P "$d/sparkle_private_key.txt" && rmdir "$d"
   ```

5. Restore it on another Mac (write the key from the password manager into a fresh private temp dir, import, then delete it):

   ```sh
   G=$(find ~/Library/Developer/Xcode/DerivedData/SimpleMapper-*/SourcePackages/artifacts -name generate_keys -type f 2>/dev/null | head -1)
   d=$(mktemp -d) && (umask 077 && pbpaste > "$d/sparkle_private_key.txt")   # key copied from the password manager
   "$G" --account SimpleMapper -f "$d/sparkle_private_key.txt"
   rm -P "$d/sparkle_private_key.txt" && rmdir "$d"
   ```

Losing the private key means installed apps can no longer accept updates. `generate_appcast` reads the key from the Keychain and may show a Keychain prompt: click Always Allow (same for `codesign` and `notarytool` prompts).

### GitHub Pages

In the GitHub repo, open Settings > Pages and set Source = GitHub Actions. Every push of `appcast.xml` to `main` then redeploys the feed.

## §1 Per release

### With /cf-ship (recommended)

Run `/cf-ship`. The project guide in `.coding-friend/skills/cf-ship-custom/SKILL.md` picks the version, writes the `CHANGELOG.md` section, bumps `project.yml`, commits `chore(release): vX.Y.Z`, pushes to `main` and runs `scripts/ship.sh`.

First release: the current `MARKETING_VERSION` (1.0.0) ships as-is, without a bump, and the `## [Unreleased]` items move into `## [1.0.0] - <date>`.

### Manually

1. Bump the version (sets `MARKETING_VERSION`, increments `CURRENT_PROJECT_VERSION` in `project.yml`; skip on the first release):

   ```sh
   scripts/bump-version.sh X.Y.Z
   ```

2. Move the `## [Unreleased]` items of `CHANGELOG.md` into a new `## [X.Y.Z] - YYYY-MM-DD` section (the GitHub Release notes come from it).
3. Commit and push:

   ```sh
   git add -- CHANGELOG.md project.yml
   git commit -m "chore(release): vX.Y.Z" -- CHANGELOG.md project.yml
   git push origin main
   ```

4. Ship:

   ```sh
   scripts/ship.sh
   ```

Outputs land in `release/export/` (gitignored): `SimpleMapper.app`, `SimpleMapper-X.Y.Z.zip`, `SimpleMapper-X.Y.Z.dmg` and the release notes `SimpleMapper-X.Y.Z.md`.

### What each script does

- `scripts/bump-version.sh [X.Y.Z]`: edits `MARKETING_VERSION` (when given) and `CURRENT_PROJECT_VERSION` (+1) in `project.yml`. Sparkle only offers an update when the build number increases. Does not commit.
- `scripts/build-and-notarize.sh`: checks Xcode 26+, the Developer ID identity, a non-empty `SUPublicEDKey`, an https `SUFeedURL` and the notary profile before anything slow; runs `xcodegen generate`; archives the Release build to `release/SimpleMapper.xcarchive`; checks signing, hardened runtime, no `get-task-allow`, macOS 13.0 minimum and the compiled app icon; re-signs Sparkle's nested helpers with Developer ID; notarizes and staples the app, zips it; builds, signs, notarizes and staples the DMG.
- `scripts/publish-release.sh [--yes] <zip>`: reads the version from the committed `project.yml`, requires branch `main`, `gh` auth, a new tag and a `## [X.Y.Z]` section in `CHANGELOG.md`; creates and pushes tag `vX.Y.Z`; creates the GitHub Release with the zip and uploads the DMG.
- `scripts/publish-appcast.sh <zip>`: runs Sparkle's `generate_appcast --account SimpleMapper --maximum-versions 0` (keeps every past item) over the new zip plus the existing `appcast.xml`, copies the result to the repo root, commits `chore(release): appcast vX.Y.Z` and pushes; the Pages workflow deploys it in about a minute.
- `scripts/ship.sh`: refuses uncommitted changes to tracked files or an existing tag `vX.Y.Z` (local or on origin), then runs the three scripts above in order and aborts if `HEAD` changes during the build.

Verify a release:

```sh
curl -fsSL https://dinhanhthi.github.io/SimpleMapper/appcast.xml | grep shortVersionString
```

## §2 Troubleshooting and rollback

- Notarization not Accepted: `build-and-notarize.sh` prints the submission id. Read the log, which names the binary that failed:

  ```sh
  xcrun notarytool log <id> --keychain-profile <profile>
  ```

- Gatekeeper check of the app or DMG:

  ```sh
  spctl -a -vvv release/export/SimpleMapper.app
  spctl -a -vvv -t open --context context:primary-signature release/export/SimpleMapper-X.Y.Z.dmg
  ```

  The app must report `source=Notarized Developer ID`. If Gatekeeper still blocks a downloaded copy, check that the release assets are the stapled files from `release/export/`.
- `no 'Developer ID Application' identity`: create the certificate (§0) and check `security find-identity -v -p codesigning`.
- `notarytool credential profile ... is missing`: run `store-credentials` (§0) or set `SIMPLEMAPPER_NOTARY_PROFILE`.
- `generate_appcast not found`: build the project once (`scripts/dev.sh`) so DerivedData holds the Sparkle tools.
- `tag vX.Y.Z already exists`: if the release is half-shipped (tag pushed but assets or appcast entry missing), finish it: if the GitHub Release itself is missing, `gh release create vX.Y.Z release/export/SimpleMapper-X.Y.Z.zip --repo dinhanhthi/SimpleMapper --title "SimpleMapper X.Y.Z" --notes-file <the ## [X.Y.Z] section of CHANGELOG.md saved to a file>`; upload any missing asset with `gh release upload vX.Y.Z release/export/<missing file> --repo dinhanhthi/SimpleMapper`; then `gh release download vX.Y.Z --repo dinhanhthi/SimpleMapper --pattern 'SimpleMapper-X.Y.Z.zip' --dir release/export --clobber` and `scripts/publish-appcast.sh release/export/SimpleMapper-X.Y.Z.zip` (`/cf-ship` does this automatically). Otherwise bump the version, or roll back the bad release below.
- Push rejected (non-fast-forward): local `main` is behind `origin/main` (e.g. a PR was merged on GitHub). Run `git fetch origin && git merge --ff-only origin/main`; if that fails, the branches diverged: rebase or merge by hand, then release again. Never force-push `main`.
- Updates not offered: check the appcast is live (curl above), the build number increased, and `SUPublicEDKey` matches the key under the `SimpleMapper` Keychain account.

### Roll back a bad release

```sh
gh release delete vX.Y.Z --repo dinhanhthi/SimpleMapper
git push origin :refs/tags/vX.Y.Z && git tag -d vX.Y.Z
git revert <appcast-commit>   # the "chore(release): appcast vX.Y.Z" commit
git push origin main
```

Reverting the appcast stops offering the update to installed apps. Users who already updated keep that version; ship a fixed, higher version to move them on.
