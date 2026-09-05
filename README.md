# omarchy-youtube-music

YouTube Music as a dropdown window anchored to the Omarchy bar (Chromium in app mode). Playback continues while the dropdown is hidden.

- Click: shows/hides instantly (no animation, opens directly in position)
- Clicking outside, focus change, or workspace switch: hides automatically
- Bar icon shows the current track; middle-click toggles play/pause

Requires `chromium` (or `google-chrome`) installed.

## Install

```bash
omarchy plugin add https://github.com/wolften/omarchy-youtube-music --enable
```

Then add it to the bar (`~/.config/omarchy/shell.json`, `right` section):

```json
{ "id": "wolften.youtube-music", "display": "icon" }
```

## Remove

```bash
omarchy plugin remove wolften.youtube-music
```

Also remove the `wolften.youtube-music` entry from `~/.config/omarchy/shell.json` if you added it manually.

## License

MIT — see [LICENSE](./LICENSE).

## Tests

```bash
node --test tests/model.test.js
```
