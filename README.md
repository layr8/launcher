# layr8 launcher

Single-file binaries and a one-line installer for the layr8 **launchers** —
each runs one coding harness as an agent on a layr8 Space, through the local
broker:

| launcher | harness |
|----------|---------|
| `8claude` | Claude Code |
| `8codex`  | Codex |
| `8goose`  | Goose |
| `8pi`     | Pi |

## Install (no Node required)

```sh
curl -fsSL https://raw.githubusercontent.com/layr8/launcher/main/install.sh | sh                        # 8claude
curl -fsSL https://raw.githubusercontent.com/layr8/launcher/main/install.sh | LAYR8_LAUNCHER=8codex sh   # or 8goose, 8pi
```

macOS and Linux (arm64 / x64). Installs to `~/.local/bin` (override with
`LAYR8_BIN_DIR`).

The launcher needs [`layr8-broker`](https://github.com/layr8/broker) on the same
machine — one broker serves every launcher and every session on it:

```sh
curl -fsSL https://raw.githubusercontent.com/layr8/broker/main/install.sh | sh
```

Then claim the agent from the portal (**Agents → Connect an agent**), run
`<launcher> install` once, and start a session with `8claude` instead of
`claude` (`8codex` instead of `codex`, and so on).

## Choosing a version

```sh
# exactly one version, a prerelease included
curl -fsSL https://raw.githubusercontent.com/layr8/launcher/main/install.sh | LAYR8_VERSION=0.1.0 sh
# the next channel: the newest release, prereleases included, followed from then on
curl -fsSL https://raw.githubusercontent.com/layr8/launcher/main/install.sh | LAYR8_UPDATE_CHANNEL=next sh
```

The channel is saved to `~/.layr8/update.json`, **the same file the broker
reads**, so choosing one here puts both programs on it.

## Staying current

The broker is a resident daemon that a service manager restarts, so it checks on
a timer. A launcher is a foreground command, so **it checks when you run it**,
replaces its own file, and re-runs the launch you just asked for. Both follow the
same channel and both only ever move forward — a tag moved backwards does not
downgrade an installed binary.

Nothing to schedule for the launcher. To keep the broker running and current:

```sh
layr8-broker service install --env <label>
```

## Distribution

Binaries are published to the public OCI registry **`ghcr.io/layr8/launcher`**,
one tag per launcher and platform (`8claude-latest-darwin-arm64`,
`8codex-latest-linux-x64` and so on). The
installer and the launcher's self-update pull anonymously from there and verify
each download against its content digest.

`LAYR8_LAUNCHER` selects which launcher to install: `8claude` (the default),
`8codex`, `8goose` or `8pi`. Each is released and versioned on its own.

This repository holds the installer script and nothing else. It is written and
reviewed elsewhere; a check in that repository fails if this published copy
drifts from it, and equally if this copy cannot be read at all — "not read" is
not "unchanged".
