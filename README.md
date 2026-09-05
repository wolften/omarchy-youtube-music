# omarchy-youtube-music

YouTube Music como janela dropdown ancorada na barra do Omarchy (Chromium em modo app). A reprodução continua enquanto o dropdown está oculto.

- Clique: mostra/oculta instantaneamente (sem animação, abre direto na posição)
- Clique fora, troca de foco ou de workspace: oculta automaticamente
- Ícone na barra mostra a faixa atual; clique do meio alterna play/pause

Requer `chromium` (ou `google-chrome`) instalado.

## Install

```bash
omarchy plugin add https://github.com/wolften/omarchy-youtube-music --enable
```

Depois adicione à barra (`~/.config/omarchy/shell.json`, seção `right`):

```json
{ "id": "wolften.youtube-music", "display": "icon" }
```

## Remove

```bash
omarchy plugin remove wolften.youtube-music
```

Remova também a entrada `wolften.youtube-music` de `~/.config/omarchy/shell.json` se tiver adicionado manualmente.

## License

MIT — see [LICENSE](./LICENSE).

## Tests

```bash
node --test tests/model.test.js
```
