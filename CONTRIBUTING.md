# Contributing

## Local setup

Symlink this repo into your Omarchy plugins directory so edits hot-reload
without reinstalling:

```bash
ln -s "$(pwd)" ~/.config/omarchy/plugins/vinicgobbi.clipboard
omarchy plugin enable vinicgobbi.clipboard
```

This plugin is a clone of the built-in `omarchy.clipboard` (own id, so
it doesn't collide with the built-in's IPC target), plus its own
`bar-widget` entry point to open it from the bar. Disable
`omarchy.clipboard` to avoid duplicate overlays, and hide the native
`omarchy.clipboard` bar icon if you had one enabled.

Both `Clipboard.qml` and `BarWidget.qml` (the plugin's entry points)
hot-reload on their own.

Validate the manifest before publishing:

```bash
omarchy plugin validate .
```

## Structure

- `manifest.json` — plugin metadata (id, kinds, entry points)
- `Clipboard.qml` — cloned from `omarchy.clipboard`'s `Clipboard.qml`:
  the overlay UI (filter, list, keyboard navigation, clear-history
  confirmation), the `wl-paste --watch` capture processes, and the
  history file read/write
- `ClipboardHistory.js` — pure helpers for `Clipboard.qml`: history
  parsing/normalization, entry dedup, and the filtered display rows
- `capture.sh` — captures the current clipboard payload as a JSON
  entry on stdout; invoked both on demand and by `wl-paste --watch`
- `BarWidget.qml` — bar icon that toggles the `Clipboard.qml` overlay.
  Follows the `omarchy.menu` pattern rather than `omarchy.power`'s:
  since the overlay is a separate top-level module (not something this
  widget loads itself via `Loader`), it forwards to the shell's
  generic `omarchy-shell shell toggle vinicgobbi.clipboard` IPC call
  instead of tracking `opened` state directly

Reuses the same history file
(`$XDG_STATE_HOME/omarchy/clipboard-history.json`) and image cache
(`$XDG_STATE_HOME/omarchy/clipboard-images`) as the built-in plugin, so
switching between them doesn't lose history. Pasting/opening entries
still shells out to the built-in `omarchy-clipboard-paste-file`,
`omarchy-clipboard-paste-text`, and `omarchy-clipboard-open` binaries.

## CI

`.github/workflows/ci.yml` runs on every push to `main` (and on pull
requests) and validates `manifest.json` and every `.qml` file with
`qmllint`, so a syntax error can't land on `main`.

## Commits and releases

Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
and are checked with [Commitizen](https://commitizen-tools.github.io/commitizen/):

```bash
pipx install commitizen
cz commit   # interactive, conventional-commits-compliant commit
```

Releases are manual: run `.github/workflows/release.yml` from the
Actions tab (`Run workflow`, on `main`). It only runs when dispatched
against `main`, and uses Commitizen to bump `manifest.json`'s version
and the changelog based on the commit types since the last release,
tags it (`vX.Y.Z`), and publishes a GitHub Release with the changelog
entry. If there's nothing to bump (no `feat`/`fix`/`BREAKING CHANGE`
commits since the last release), it's a no-op — no tag, no release.
