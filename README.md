# omarchy-plugin-clipboard

A clipboard manager overlay for the [Omarchy](https://omarchy.org/) shell,
cloned from the built-in `omarchy.clipboard`. Starting point for adding
custom clipboard-management features on top of the native behavior.

## What it does

- Everything the native `omarchy.clipboard` overlay has: text and image
  history, fuzzy filtering, keyboard navigation, paste/copy-only/open
  actions, and per-entry or full-history clearing.
- Watches the Wayland clipboard in the background (`wl-paste --watch`)
  and records every copy to
  `$XDG_STATE_HOME/omarchy/clipboard-history.json`, shared with the
  built-in plugin.
- Adds a bar icon (unlike the native `omarchy.clipboard`, which has no
  bar widget of its own) that opens the overlay with a click.

## Preview

_TODO: add a preview screenshot once the UI has diverged from the
built-in._

## Usage

Click the clipboard icon in the bar to open the overlay.

## Install

```bash
omarchy plugin add https://github.com/vinicgobbi/omarchy-plugin-clipboard.git --enable
```

Disable the built-in `omarchy.clipboard` overlay to avoid duplicate
clipboard watchers/overlays.

## Update

```bash
omarchy plugin update vinicgobbi.clipboard
```

## Uninstall

```bash
omarchy plugin remove vinicgobbi.clipboard
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, the plugin's
file structure, and the commit/release process.

## License

[MIT](LICENSE)
