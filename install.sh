#!/bin/sh
# layr8 launcher installer. Pulls the single-file binary for this OS/arch from
# the public OCI registry (ghcr.io/layr8/launcher) — anonymous, no Node, no npm,
# no GitHub login. The binary self-updates after this, forward only, on the same
# channel the broker follows.
#
# Published from the public layr8/launcher repository — layr8/agents is private,
# so only that copy can be curled without a GitHub login:
#
#   curl -fsSL https://raw.githubusercontent.com/layr8/launcher/main/install.sh | sh
#
# This file is the source; scripts/check-public-installer.mjs compares the
# published copy with it.
#
# Env:
#   LAYR8_LAUNCHER  which launcher to install: 8claude (default)
#   LAYR8_BIN_DIR   install dir, default ~/.local/bin
#   LAYR8_VERSION   install exactly this version, e.g. 0.2.0-rc.1
#   LAYR8_UPDATE_CHANNEL
#                   latest (default: newest stable) or next (newest release,
#                   prereleases included). A channel given here is saved to
#                   ~/.layr8/update.json — the SAME file the broker reads — so
#                   both programs' own update checks keep following it.
#   LAYR8_CHANNEL   the broker installer's spelling of the same thing, accepted
#                   so one documented word works for both. A SESSION already
#                   exports LAYR8_CHANNEL=1 to mean "the Layr8 bridge is on"
#                   (claude-code/bin/8claude), so a `curl … | sh` typed inside
#                   a running session arrives with LAYR8_CHANNEL=1 — a value
#                   that is not a channel. Measured on 2026-09-24: the broker's
#                   own published one-liner dies there with "LAYR8_CHANNEL must
#                   be latest or next (got 1)". This installer says so and goes
#                   on with the default instead of refusing to install.
set -eu

REGISTRY="ghcr.io"
IMAGE="layr8/launcher"
BIN="${LAYR8_LAUNCHER:-8claude}"
# oras' empty config ({} = 2 bytes); the manifest's OTHER sha256 is the binary.
EMPTY_CONFIG="44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
MANIFEST_ACCEPT="application/vnd.oci.image.manifest.v1+json"

case "$BIN" in
  8claude) : ;;
  *) echo "LAYR8_LAUNCHER must be 8claude (got ${BIN})" >&2; exit 1 ;;
esac

version="${LAYR8_VERSION:-}"
version="${version#v}"
channel="${LAYR8_UPDATE_CHANNEL:-}"
if [ -z "$channel" ] && [ -n "${LAYR8_CHANNEL:-}" ]; then
  case "${LAYR8_CHANNEL}" in
    latest | next) channel="${LAYR8_CHANNEL}" ;;
    *)
      echo "NOTE: LAYR8_CHANNEL is '${LAYR8_CHANNEL}', which is not an update channel — a running" >&2
      echo "      Layr8 session exports LAYR8_CHANNEL=1 to mean something else. Ignoring it." >&2
      echo "      To choose a channel here, set LAYR8_UPDATE_CHANNEL=latest|next." >&2
      ;;
  esac
fi

if [ -n "$version" ] && [ -n "$channel" ]; then
  echo "set LAYR8_VERSION or LAYR8_CHANNEL, not both" >&2; exit 1
fi
if [ -n "$version" ] && ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "LAYR8_VERSION is not a version: ${version}" >&2; exit 1
fi
case "$channel" in
  "" | latest | next) : ;;
  *) echo "LAYR8_CHANNEL must be latest or next (got ${channel})" >&2; exit 1 ;;
esac

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) echo "unsupported OS: $os" >&2; exit 1 ;;
esac
case "$arch" in
  arm64 | aarch64) arch="arm64" ;;
  x86_64 | amd64) arch="x64" ;;
  *) echo "unsupported arch: $arch" >&2; exit 1 ;;
esac

api="https://${REGISTRY}/v2/${IMAGE}"

# 1. anonymous pull token (public package).
#
# Optional, unlike the broker's copy of this installer. ghcr.io hands out a
# token to anyone for a public package; a registry with no auth at all answers
# this endpoint 404, and there is then nothing to send. Failing here would mean
# the only way to exercise this script end to end is against ghcr.io, which is
# the one thing a pre-release check cannot do — so `launcher/test/live-update.sh`
# runs the real shell against a local registry:2 instead. A registry that DOES
# want auth still fails, one step later, where the message can name the tag.
token="$(curl -fsSL "https://${REGISTRY}/token?scope=repository:${IMAGE}:pull" 2>/dev/null \
  | tr ',' '\n' | grep '"token"' | head -1 | sed 's/.*"token":"//; s/".*//')" || token=""
if [ -n "$token" ]; then
  auth="Authorization: Bearer ${token}"
else
  auth="Accept-Encoding: identity"
fi

fetch_manifest() {
  curl -fsSL -H "$auth" -H "Accept: ${MANIFEST_ACCEPT}" "${api}/manifests/$1"
}

# 2. the manifest: a version's own tag, or the channel's tag. Every tag is
# prefixed with the launcher's name, so one registry repository can carry more
# than one launcher without either one ever installing the other's build.
if [ -n "$version" ]; then
  tag="${BIN}-${version}-${os}-${arch}"
  manifest="$(fetch_manifest "$tag")" || { echo "no published ${BIN} ${version} for ${os}-${arch} (${tag})" >&2; exit 1; }
elif [ "$channel" = "next" ]; then
  tag="${BIN}-next-${os}-${arch}"
  if ! manifest="$(fetch_manifest "$tag" 2>/dev/null)"; then
    # next-* is maintained from the first release after it was introduced;
    # until then the newest release of any kind is the stable one.
    echo "no ${tag} published yet; installing latest instead"
    tag="${BIN}-latest-${os}-${arch}"
    manifest="$(fetch_manifest "$tag")" || { echo "couldn't fetch the manifest for ${tag}" >&2; exit 1; }
  fi
else
  tag="${BIN}-latest-${os}-${arch}"
  manifest="$(fetch_manifest "$tag")" || { echo "couldn't fetch the manifest for ${tag}" >&2; exit 1; }
fi

published="$(printf '%s' "$manifest" | tr ',{}' '\n\n\n' \
  | grep '"org.opencontainers.image.version"' | head -1 | sed 's/.*"org.opencontainers.image.version":"//; s/".*//')"
if [ -n "$version" ] && [ "$published" != "$version" ]; then
  echo "tag ${tag} carries version '${published}', not ${version} — aborting" >&2; exit 1
fi

# 3. the binary layer digest = the sha256 that isn't the empty config
digest="$(printf '%s' "$manifest" | grep -o '[0-9a-f]\{64\}' | grep -v "${EMPTY_CONFIG}" | head -1)"
[ -n "$digest" ] || { echo "no binary layer in the manifest" >&2; exit 1; }

dest="${LAYR8_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$dest"
tmp="$(mktemp)"

echo "Installing ${BIN} ${published:-?} (${os}-${arch}, ${tag}) → ${dest}/${BIN}"
curl -fsSL -H "$auth" "${api}/blobs/sha256:${digest}" -o "$tmp"

# 4. verify the blob against its content digest (integrity for free)
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "$tmp" | awk '{print $1}')"
else
  got="$(shasum -a 256 "$tmp" | awk '{print $1}')"
fi
if [ "$digest" != "$got" ]; then
  echo "checksum mismatch (want ${digest}, got ${got}) — aborting" >&2
  rm -f "$tmp"; exit 1
fi

# An existing 8claude may be the symlink an older, git-checkout install left
# behind. Writing through it would overwrite a file in someone's clone, so take
# it out of the way first; `mv` onto a symlink follows it.
[ -L "${dest}/${BIN}" ] && rm -f "${dest}/${BIN}"
chmod +x "$tmp"
mv "$tmp" "${dest}/${BIN}"

echo "Installed ${dest}/${BIN} (sha256:${got})"

# 5. remember an explicitly chosen channel. This is the broker's file, on
# purpose: one channel, both programs, one thing for a user to choose.
if [ -n "$channel" ]; then
  mkdir -p "$HOME/.layr8"
  printf '{"channel":"%s"}\n' "$channel" > "$HOME/.layr8/update.json"
  echo "Update channel: ${channel} (saved to ~/.layr8/update.json — the broker follows it too)"
fi

case ":${PATH}:" in
  *":${dest}:"*) : ;;
  *) echo "NOTE: ${dest} is not on your PATH — add it, e.g.  export PATH=\"${dest}:\$PATH\"" ;;
esac
if "${dest}/${BIN}" --version >/dev/null 2>&1; then
  echo "OK. Next:"
  echo "  1. ${BIN} install       # connect Claude Code to the agent this machine's broker holds"
  echo "  2. ${BIN}               # start a session"
fi
