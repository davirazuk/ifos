# Qobuz-DL no celular

Um app Android de verdade para o Qobuz-DL — ícone próprio, tela cheia, sem
navegador, sem terminal visível. Por baixo, o Termux roda o mesmo backend
Python/Flask do `qobuz-dl-gui` da área de trabalho, escondido; este app é só
uma `WebView` fina apontando para `http://127.0.0.1:8765/`.

## Por que não é só o app do Qobuz-DL empacotado direto

O app upstream (`qobuz-dl-gui`) é um programa de desktop: parte dele espera
uma janela de verdade (`pywebview`), e um dos módulos de rotas
(`utility_routes.py`) importava isso incondicionalmente, o que derrubava o
processo inteiro assim que o Termux tentava importar o módulo — sem janela,
sem `pywebview` de verdade, sem app. `gtk-and-pwa.patch` (a mesma que o
`qobuz-dl-gui` da área de trabalho usa) resolve isso tornando esse import
tardio, e o resto do patch adiciona um manifesto PWA + service worker, que
este app nem usa (ele já é nativo), mas não atrapalha.

## Instalação

**1. No celular:** instale o Termux e o Termux:Boot — a versão da Play Store
do Termux está descontinuada, use os builds do GitHub:

- <https://github.com/termux/termux-app/releases> (`termux-app_*_arm64-v8a.apk`
  na maioria dos celulares)
- <https://github.com/termux/termux-boot/releases>

Abra o Termux:Boot uma vez (só isso, pode fechar depois) — é assim que o
Android concede a ele a permissão de rodar no boot.

**2. Dentro do Termux**, cole isto e rode (pede internet; a maior parte do
tempo é `pkg install`):

```sh
curl -sL https://raw.githubusercontent.com/davirazuk/ifos/main/mobile/qobuz-dl-android/termux-setup.sh | bash
```

Isso clona o `qobuz-dl-gui` (num commit fixo, não o HEAD do upstream — ver
"Por que fixar um commit" abaixo), aplica o patch, instala as dependências
Python e deixa tudo pronto para iniciar sozinho no próximo boot. Ele também
inicia o backend agora, então dá para testar sem reiniciar o celular.

**3. Numa máquina com o Android SDK** (ou usando `build.sh`, que baixa um
sozinho — não precisa de Android Studio nem Gradle):

```sh
./build.sh install   # build/QobuzDL.apk + adb install -r, com o celular plugado
```

Sem um celular plugado, `./build.sh` sozinho só gera o APK; instale manualmente
depois (`adb install build/QobuzDL.apk`, ou copie o APK para o celular e abra
com um gerenciador de arquivos — "instalar de fontes desconhecidas" precisa
estar permitido).

## Por que fixar um commit

`gtk-and-pwa.patch` mira linhas específicas de `gui_app.py`,
`utility_routes.py` e outros arquivos do commit `032c566` (release v1.4.1).
Se o `termux-setup.sh` seguisse o HEAD do upstream, um refactor lá quebraria o
`git apply` aqui sem aviso — trocando "atualiza sozinho" por "atualiza sozinho,
às vezes para uma versão quebrada". Atualizar o pin é seguro (é só mudar
`PIN_COMMIT` e regerar o patch a partir de um clone limpo), só não deve ser
automático.

## Pasta de download

O backend roda dentro do Termux, então "Pasta de Download Padrão" nas
configurações do app precisa ser um caminho que o Termux enxerga — o botão
"Browse" já abre o seletor de pastas nativo do Android (não o do pywebview,
que não existe aqui) e resolve para um caminho de verdade em
`/storage/emulated/0/...`, então normalmente não precisa digitar nada à mão.
