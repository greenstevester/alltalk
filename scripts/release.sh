#!/usr/bin/env bash
#
# release.sh — build, Developer ID sign, notarize, staple, publish a GitHub
# release, and bump the Homebrew cask for AllTalk.
#
# One-time prerequisites (only you can do these — see README/Signing):
#   1. Apple Developer Program membership.
#   2. A "Developer ID Application" certificate in your login Keychain.
#   3. A notarytool keychain profile:
#        xcrun notarytool store-credentials AllTalkNotary \
#          --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
#   4. gh authenticated with push access to the repo and the tap.
#
# Usage:
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh 0.1.1
#
# Env overrides:
#   SIGN_ID         (required) codesigning identity, exactly as in `security find-identity`
#   NOTARY_PROFILE  notarytool keychain profile name        (default: AllTalkNotary)
#   REPO            GitHub repo for the release             (default: greenstevester/alltalk)
#   TAP_REPO        Homebrew tap repo to bump               (default: greenstevester/homebrew-tap)
#   RELEASE_YES=1   skip the confirmation prompt (for CI)
#   DRY_RUN=1       build + sign + notarize only; don't publish or bump the cask

set -euo pipefail

VERSION="${1:?usage: $0 <version>   e.g. $0 0.1.1}"
SIGN_ID="${SIGN_ID:?set SIGN_ID to your 'Developer ID Application: Name (TEAMID)' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AllTalkNotary}"
REPO="${REPO:-greenstevester/alltalk}"
TAP_REPO="${TAP_REPO:-greenstevester/homebrew-tap}"

PROJECT="AllTalk.xcodeproj"
SCHEME="AllTalk"
APP_NAME="AllTalk.app"
ENTITLEMENTS="AllTalk/AllTalk.entitlements"

# brew install reference derived from the tap repo: greenstevester/homebrew-tap -> greenstevester/tap/alltalk
TAP_USER="${TAP_REPO%%/*}"
TAP_SHORT="${TAP_REPO##*/homebrew-}"
BREW_REF="$TAP_USER/$TAP_SHORT/alltalk"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
DERIVED="$WORK/dd"
APP="$DERIVED/Build/Products/Release/$APP_NAME"
ZIP="$WORK/AllTalk-$VERSION.zip"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------- preflight
say "Checking prerequisites"
for t in xcodebuild codesign xcrun ditto shasum gh git security spctl; do
  command -v "$t" >/dev/null || die "missing required tool: $t"
done
security find-identity -v -p codesigning | grep -qF "$SIGN_ID" || die \
  "signing identity not found in keychain: $SIGN_ID
available:
$(security find-identity -v -p codesigning)"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || die \
  "notarytool profile '$NOTARY_PROFILE' not set up. Create it with:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"

PROJ_VER="$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | sed -E 's/.*= (.*);/\1/' || true)"
[ "$PROJ_VER" = "$VERSION" ] || echo \
  "warning: project MARKETING_VERSION is '$PROJ_VER' but releasing '$VERSION' — update it in Xcode to match if you care."

# --------------------------------------------------------------------- build
say "Building Release (unsigned; signed explicitly below)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null
[ -d "$APP" ] || die "build did not produce $APP"

# --------------------------------------------------------------------- sign
say "Signing with Developer ID + hardened runtime"
# Single-bundle app, so one codesign is enough. When Phase 3 bundles llama-server
# (and its dylibs) inside the .app, sign those nested binaries inside-out BEFORE this.
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# --------------------------------------------------------------------- notarize
say "Notarizing (waits for Apple, ~1-5 min)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

say "Stapling the notarization ticket"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip the now-stapled app for distribution

if spctl -a -vvv --type install "$APP" 2>&1 | grep -q "accepted"; then
  echo "Gatekeeper: accepted (Notarized Developer ID) ✓"
else
  echo "warning: spctl did not report 'accepted' — inspect before distributing"
fi

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
say "Built notarized AllTalk-$VERSION.zip  (sha256 $SHA)"

if [ "${DRY_RUN:-}" = 1 ]; then
  cp "$ZIP" "$ROOT/"
  echo "DRY_RUN=1 — stopping before publish. Artifact copied to $ROOT/AllTalk-$VERSION.zip"
  exit 0
fi

# --------------------------------------------------------------------- confirm
if [ "${RELEASE_YES:-}" != 1 ]; then
  read -r -p "Publish v$VERSION to $REPO and bump the cask in $TAP_REPO? [y/N] " ans
  case "$ans" in y|Y) ;; *) die "aborted" ;; esac
fi

# --------------------------------------------------------------------- release
say "Publishing GitHub release v$VERSION"
NOTES="$WORK/notes.md"
cat > "$NOTES" <<EOF
AllTalk $VERSION — signed and notarized, so it opens with a normal double-click.

## Install

- \`brew install --cask $BREW_REF\`, or
- download \`AllTalk-$VERSION.zip\` below, unzip, and move \`AllTalk.app\` to /Applications.

## Requirements

AllTalk drives a local llama.cpp server it starts and stops for you:

    brew install llama.cpp

then download the Voxtral model (see the README). The app handles the rest.
EOF
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "AllTalk $VERSION" --notes-file "$NOTES"

# --------------------------------------------------------------------- cask bump
say "Bumping the Homebrew cask in $TAP_REPO"
TAP="$WORK/tap"
git clone --depth 1 "git@github.com:$TAP_REPO.git" "$TAP" >/dev/null 2>&1
CASK="$TAP/Casks/alltalk.rb"
[ -f "$CASK" ] || die "cask not found at $CASK"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
ruby -c "$CASK" >/dev/null || die "cask has a syntax error after the bump"
(
  cd "$TAP"
  git add Casks/alltalk.rb
  git commit -q -m "alltalk $VERSION"
  git push -q
)

say "Done — released v$VERSION and bumped the cask (sha256 $SHA)."
echo "    brew update && brew upgrade --cask $BREW_REF"
