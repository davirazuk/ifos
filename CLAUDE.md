# Instruções para o Claude — leia isto antes de qualquer coisa

Este arquivo existe para duas coisas: para você não gastar crédito
redescobrindo o que já foi descoberto, e para você não estragar o computador
de ninguém.

**Leia este arquivo inteiro. Depois vá direto ao trabalho.** Ele foi escrito
para substituir uma hora de exploração. Se algo aqui responde a sua pergunta,
não abra o arquivo para conferir.

---

## 1. A regra que não se quebra: isto é um repositório, não um sistema

O IFOS é uma distribuição Linux. Este repositório é o **código-fonte** dela.
A máquina onde você está rodando **não é** uma máquina IFOS, e o computador do
usuário **não é** o que você está editando.

**Nunca execute nada que mexa na máquina.** Nem para testar, nem para
"verificar se funciona", nem porque parece inofensivo:

| Nunca rode | Por quê |
| --- | --- |
| `ifos-update` | atualiza a máquina de verdade e reinicia ela |
| `ifos-gpu --fix`, `--fallback`, `--write-nvidia-config` | troca driver, escreve em `/etc`, carrega módulo |
| `install-ifos` | formata disco |
| `pacman -S`, `-R`, `-Syu` | mexe nos pacotes da máquina |
| `systemctl enable/start/disable` | mexe nos serviços da máquina |
| `mkinitcpio`, `modprobe`, `usermod`, `udevadm control` | mexem no sistema |
| qualquer coisa escrevendo em `/etc`, `/usr`, `/boot` | idem |

O que **é** seguro, e é como se testa aqui:

```
bash tools/test-tools.sh        # 213 verificações, o teste principal
python3 tools/test-launcher.py  # o lançador (use python3.12 se o gi falhar)
python3 tools/check-icons.py    # os glifos das fontes
bash -n <script>                # sintaxe
shellcheck -S warning <script>
fish -n <arquivo .fish>
i3 -C -c airootfs/etc/skel/.config/i3/config
udevadm verify airootfs/etc/udev/rules.d/*.rules
systemd-analyze verify airootfs/etc/systemd/system/*.service
```

Escrever arquivos **dentro do repositório** é o trabalho. Escrever fora dele
não é.

Se o usuário pedir "conserta o meu PC", a resposta é: eu conserto o código, e
você roda `sudo ifos-update` na sua máquina. Você não tem acesso à máquina
dele e não deve fingir que tem.

---

## 2. Como não gastar crédito à toa

Coisas que já custaram sessões inteiras e não precisam custar de novo:

- **Não leia arquivo inteiro para saber se algo existe.** Use `grep`/`Grep`.
  `ifos-gpu` tem 1100 linhas, `install-ifos` tem 900, `ifos-launcher` tem 1600.
  Ler os três é meia sessão.
- **Os testes são a especificação.** `tools/test-tools.sh` diz o que cada
  ferramenta tem que fazer, em português, com o motivo escrito no comentário.
  Ler o teste é mais barato e mais informativo que ler o código.
- **Rode o teste antes de investigar.** Se ele passa, o comportamento está
  como foi decidido; a dúvida é sobre outra coisa.
- **Não re-explore o repositório.** O mapa está na seção 4.
- **Não repita a análise para o usuário.** Ele já sabe o que pediu. Faça.
- **Um PR por assunto**, com o teste junto. Não acumule cinco assuntos.

---

## 3. O que já se sabe (não redescubra)

### O ambiente desta sessão

- O proxy **bloqueia `archlinux.org` e `aur.archlinux.org` com 403**. Não dá
  para conferir nome de pacote daqui. Não insista, não tente contornar, e
  **diga isso ao usuário** quando adicionar um nome novo.
- A verificação de nomes acontece em `tools/check-packages.sh`, que roda no
  contêiner de build (`build.sh` chama antes do `pacstrap`). Nome de pacote
  novo vai em `PACKAGES` do `install-ifos` ou no catálogo — os dois são
  conferidos lá. **Nunca invente um nome de pacote do AUR.** Já aconteceu:
  `jstest-gtk` não existe, um aluno viu `no package found for targets`.
- `python3` padrão é 3.11 e o `gi` é compilado para 3.12. Use
  `/usr/bin/python3.12` para qualquer coisa com GTK.
- Não dá para construir o ISO nem subir uma VM aqui. **Diga isso** ao entregar.

### A paleta do IFOS

`ifos-theme` troca de tema substituindo estes hexes por posição. **Toda cor
nova tem que sair desta lista**, ou ela sobrevive à troca de tema e fica no
meio da paleta nova:

```
base #10241d   surface #1b3a2e   hover #24503f   deep #04150f
text #e8f5e9   subtext #b9d4c6   dim #7fa392
accent #00a86b accent-2 #7ed957  bright #00c47d
```

### Armadilhas técnicas já pagas

- **`70-uaccess.rules` do systemd só dá acesso a `ID_INPUT_JOYSTICK`.** Mouse
  e teclado são só do root. Por isso `ifos-mouse` lê botões por
  `xinput test-xi2 --root` e não por `/dev/input/event*`.
- **systemd não remove aspas** ao dividir `$VAR` no `ExecStart`. Por isso
  `airootfs/etc/default/earlyoom` não tem uma aspa sequer.
- **`mkinitcpio` lê `/etc/mkinitcpio.conf.d/*.conf` em ordem e o último
  `HOOKS` vence.** `ifos-nvidia.conf` ordena *antes* de `ifos.conf` (traço vem
  antes de ponto), por isso o arquivo se chama `nvidia.conf`.
- **`pacman --noconfirm` responde *não*** à pergunta "remover o pacote em
  conflito?". Por isso a troca de driver remove `nvidia-open-dkms` pelo nome
  antes de instalar `nvidia-dkms`.
- **`xinput list --short` separa nome e id com TAB**, não espaço.
- **`curl` trata `[` `]` como faixa de URL.** Precisa de `-g`.
- **`pkill -f` casa contra a linha de comando de tudo na máquina.** Já matou o
  shell do próprio teste. Use pidfile conferido contra `/proc/$pid/cmdline`.
- **`notify-send` trava sem dbus.** `|| true` não resolve; use `timeout 3`.
- **Glifos se perdem no caminho.** Escreva por codepoint em Python e confira
  lendo do disco. `tools/check-icons.py` existe para isso.
- **`picom` tem `unredir-if-possible` desligado por padrão**, o que deixa jogo
  em tela cheia composto — foi a causa do "megabonk travando".

### Os quatro drivers da NVIDIA

Não existe *um* driver da NVIDIA. Instalar o errado **não dá erro**: o módulo
carrega, não assume placa nenhuma, e a máquina desenha no processador parecendo
configurada. A tabela está em `ifos-gpu` (`nvidia_arch`, `nvidia_driver_for`):

| Geração | Driver |
| --- | --- |
| Blackwell/Ada/Ampere/Turing | `nvidia-open-dkms` |
| Volta/Pascal/Maxwell | `nvidia-dkms` |
| Kepler | `nvidia-470xx-dkms` (AUR — só nomear, nunca instalar sozinho) |
| Fermi | `nvidia-390xx-dkms` (AUR — idem) |
| não reconhecida | `nvidia-dkms`, que cobre mais hardware |

`nvidia_bound()` — contar as placas em `/proc/driver/nvidia/gpus/` — é a
verdade. `module_loaded nvidia` não é.

### Lições de processo

- **Vá ao histórico antes de adivinhar intenção visual.** O usuário pediu duas
  vezes para desfazer uma mudança na polybar; `git log --follow` mostrou
  exatamente qual commit tinha introduzido as bordas. Adivinhar custou duas
  rodadas.
- **Não faça mudança que você não consegue medir.** Se não dá para mostrar que
  melhora, não entra.
- **Todo PR conflita.** `main` recebe squash-merge, então os patch-ids nunca
  batem. `git fetch origin main && git merge origin/main`, confira **por
  conteúdo** que nada de `main` se perde (as vezes o lado do `main` é o seu
  próprio código numa versão mais velha), e resolva.

---

## 4. Mapa do repositório

```
packages.x86_64          pacotes do ISO ao vivo
profiledef.sh            perfil archiso
build.sh                 constrói o ISO (roda check-packages.sh antes)
grub/ efiboot/ syslinux/ menus de boot do pendrive

airootfs/                vira / no ISO
  usr/local/bin/
    install-ifos         o instalador (particiona, pacstrap, chroot)
    ifos-update          atualiza uma máquina instalada a partir do git
    ifos-gpu             diagnóstico e conserto de vídeo
    ifos-launcher        o lançador gráfico (GTK, python3.12)
    ifos-software        catálogo de programas
    ifos-mouse           DPI e aceleração
    ifos-controller      gamepads
    ifos-theme           troca de paleta
  usr/share/ifos/
    branding-sync.sh     copia tudo do IFOS para um alvo — TODO ARQUIVO NOVO
                         PRECISA DE UMA LINHA AQUI OU NUNCA CHEGA NA MÁQUINA
    apps.d/*.list        catálogo: nome|descrição|pacotes|origem
  etc/skel/              a configuração do desktop (i3, polybar, rofi, dunst,
                         picom, fish, gtk, qt5ct/qt6ct)
  etc/systemd/system/    serviços do IFOS
  etc/udev/rules.d/      permissões de dispositivo

tools/
  test-tools.sh          213 verificações — o teste principal
  test-launcher.py       o lançador
  check-packages.sh      confere nomes de pacote no contêiner de build
  check-icons.py         confere glifos
```

**Três lugares que sempre andam juntos.** Ao adicionar um arquivo ou serviço:

1. o arquivo em `airootfs/…`
2. uma linha em `branding-sync.sh` (senão máquina nenhuma recebe)
3. `install-ifos` (instalação nova) **e** `ifos-update` (máquina que já existe)

Esquecer o 2 é o erro mais comum e é silencioso.

`ifos-update` lê `^systemctl enable X` do `install-ifos` sozinho, então serviço
novo só precisa entrar no instalador, na margem esquerda.

---

## 5. Fluxo de trabalho

```
git checkout -b claude/<assunto>     # nunca commite direto na main
# … trabalho, com teste junto …
bash tools/test-tools.sh
git push -u origin claude/<assunto>
```

Abra o PR e **faça o merge na `main`** — `ifos-update` puxa da `main`, então
código que não está lá não chega em máquina nenhuma. Rodapé obrigatório no PR:

```
---
_Generated by [Claude Code](https://claude.ai/code)_
```

Mensagem de commit e corpo de PR em português, dizendo **qual era o defeito**,
não só o que mudou. O README é escrito no mesmo tom e deve acompanhar mudança
de comportamento.

---

## 6. Onde as coisas estavam paradas

Última coisa feita: NVIDIA (PRs #39 e #40) e o conserto automático no
`ifos-update`. O usuário tem uma máquina com NVIDIA que não funcionava, e a
causa era driver errado para a geração da placa — nada disso foi visto num boot
real ainda.

O que falta saber, e só o usuário pode responder:

- O `ifos-gpu --check` na máquina dele, depois de `sudo ifos-update` e reiniciar.
  Isso diz qual é a placa e o que o driver fez.
- Se o botão de DPI do mouse Redragon já é detectado por `ifos-mouse --test`.

Pedido permanente do usuário: continuar melhorando desempenho, drivers,
correções de bug e aparência, e fazer tudo funcionar sem configuração manual.
