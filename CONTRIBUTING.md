# Contributing

## Local setup

`omarchy plugin validate .` rejects a plugin folder that contains a
symlink, so a plain `ln -s` of this repo into
`~/.config/omarchy/plugins/` won't load. Clone it there instead
(a real, separate working copy — like `omarchy plugin add` would
leave):

```bash
git clone "$(pwd)" ~/.config/omarchy/plugins/vinicgobbi.clipboard
omarchy plugin enable vinicgobbi.clipboard
```

To pick up local edits without re-cloning, add this repo as a remote
in the installed copy and pull:

```bash
git -C ~/.config/omarchy/plugins/vinicgobbi.clipboard remote add dev "$(pwd)"
git -C ~/.config/omarchy/plugins/vinicgobbi.clipboard pull dev main
```

This plugin is a clone of the built-in `omarchy.clipboard` (own id, so
it doesn't collide with the built-in's IPC target). Disable
`omarchy.clipboard` to avoid duplicate clipboard watchers.

`BarWidget.qml` and `Panel.qml` (the plugin's UI) hot-reload on their
own once the installed copy is updated.

Validate the manifest before publishing:

```bash
omarchy plugin validate .
```

## Structure

- `manifest.json` — plugin metadata (id, kinds, entry points)
- `BarWidget.qml` — bar icon; loads `Panel.qml` via a `Loader` and
  forwards open/close/toggle to it, same shape as `vinicgobbi.power`
- `Panel.qml` — the popup itself: filterable history list, paste on
  row click, copy/delete inline actions, and an eye button on image
  entries that opens a `PopupCard` preview instead of rendering every
  image inline. Also owns the `wl-paste --watch` capture processes and
  the history file read/write (loaded eagerly by the `Loader` above,
  so it's alive for the whole session, not just while the popup is
  open)
- `ClipboardHistory.js` — pure helpers for `Panel.qml`: history
  parsing/normalization, entry dedup, and the filtered display rows
- `capture.sh` — captures the current clipboard payload as a JSON
  entry on stdout; invoked both on demand and by `wl-paste --watch`

Reuses the same history file
(`$XDG_STATE_HOME/omarchy/clipboard-history.json`) and image cache
(`$XDG_STATE_HOME/omarchy/clipboard-images`) as the built-in plugin, so
switching between them doesn't lose history. Pasting/copying entries
still shells out to the built-in `omarchy-clipboard-paste-file` and
`omarchy-clipboard-paste-text` binaries.

## CI

`.github/workflows/ci.yml` runs on every push to `main` (and on pull
requests): it validates `manifest.json`, runs Shellcheck on any shell
scripts, and lints every `.qml` file with `qmllint`, so a syntax error
can't land on `main`.

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
