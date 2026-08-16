#!/usr/bin/env python3
"""test-launcher.py — check the launcher's matching rules against a fake machine.

The launcher decides three things without asking anyone: which desktop file
belongs to a catalog entry, whether that entry is already installed, and
whether a system tile has anything behind it. Each of those has been wrong in a
way that shipped — the Steam tile drawing Hollow Knight's icon and launching
it, a catalog offering to install a program that was already there, a tile that
did nothing when clicked — and none of them is visible in a diff.

So this builds a fake machine out of desktop files and stub executables and
checks the answers. Run it with the python that has gi:

    /usr/bin/python3.12 tools/test-launcher.py
"""
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
LAUNCHER = os.path.join(HERE, "..", "airootfs", "usr", "local", "bin", "ifos-launcher")

PASS = 0
FAIL = 0


def check(desc: str, ok: bool, detail: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"    \033[1;32m✓\033[0m {desc}")
    else:
        FAIL += 1
        print(f"    \033[1;31m✗\033[0m {desc}")
        if detail:
            print("        " + detail)


def load_launcher():
    spec = importlib.util.spec_from_loader(
        "ifos_launcher",
        importlib.machinery.SourceFileLoader("ifos_launcher", LAUNCHER),
    )
    module = importlib.util.module_from_spec(spec)
    argv, sys.argv = sys.argv, ["ifos-launcher"]
    try:
        spec.loader.exec_module(module)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return module


def write_desktop(directory: str, name: str, body: str) -> None:
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, name), "w", encoding="utf-8") as handle:
        handle.write(body)


def write_stub(directory: str, name: str) -> None:
    """A desktop entry whose Exec is not on PATH is dropped by GIO entirely.

    Learned the hard way: a fixture without these produced an empty
    application list and every assertion in it passed for the wrong reason.
    """
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, name)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("#!/bin/sh\nexit 0\n")
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def main() -> int:
    root = tempfile.mkdtemp(prefix="ifos-launcher-test.")
    apps = os.path.join(root, "applications")
    bins = os.path.join(root, "bin")
    catalog = os.path.join(root, "apps.d")
    os.makedirs(catalog)

    # ── the machine ──────────────────────────────────────────────────────────
    # Steam, with two games installed. Every game's desktop entry runs `steam`
    # with a game id, which is what used to make the Steam tile resolve to a
    # game: same executable, and whichever GIO returned first won.
    write_stub(bins, "steam")
    write_stub(bins, "krita")
    write_stub(bins, "flatpak")
    write_desktop(apps, "steam.desktop", """[Desktop Entry]
Type=Application
Name=Steam
Exec=steam %U
Icon=steam
Categories=Network;FileTransfer;Game;
""")
    write_desktop(apps, "0000-hollow-knight.desktop", """[Desktop Entry]
Type=Application
Name=Hollow Knight
Exec=steam steam://rungameid/367520
Icon=steam_icon_367520
Categories=Game;
""")
    write_desktop(apps, "0001-celeste.desktop", """[Desktop Entry]
Type=Application
Name=Celeste
Exec=steam steam://rungameid/504230
Icon=steam_icon_504230
Categories=Game;ActionGame;
""")
    # Discord installed as a Flatpak: no `discord` binary anywhere, a desktop
    # entry that runs flatpak, and pacman has never heard of it. The Exec is an
    # absolute path because that is what flatpak writes - and GIO drops an entry
    # whose executable does not exist whether the path is absolute or not, so
    # the stub has to be at the path the entry names.
    write_desktop(apps, "com.discordapp.Discord.desktop", f"""[Desktop Entry]
Type=Application
Name=Discord
Exec={os.path.join(bins, "flatpak")} run --branch=stable com.discordapp.Discord
Icon=com.discordapp.Discord
""")

    # A second section, so the key-versus-title matching has something to get
    # wrong: this one is "browsers" on disk and "Internet" on screen.
    with open(os.path.join(catalog, "10-browsers.list"), "w", encoding="utf-8") as handle:
        handle.write("Firefox|Navegador da Mozilla|firefox|repo\n")

    with open(os.path.join(catalog, "20-gaming.list"), "w", encoding="utf-8") as handle:
        handle.write(
            "Steam|Loja e lançador de jogos da Valve|steam|multilib\n"
            "Discord|Conversa por voz e texto|discord|repo\n"
            "Krita|Pintura digital|krita|repo\n"
            "Kit Redes|Tudo para redes|wireshark-qt nmap iperf3|repo\n"
            "Blender|Modelagem 3D|blender|repo\n"
        )

    env = dict(os.environ)
    env["XDG_DATA_DIRS"] = root
    env["PATH"] = bins + os.pathsep + env.get("PATH", "")
    env["IFOS_CATALOG_DIR"] = catalog
    # No pacman in the fixture: every catalog entry starts out "not installed",
    # which is exactly the state the reconciliation pass has to correct.
    os.environ.update(env)

    module = load_launcher()
    catalog_obj = module.Catalog()

    print("\n  ifos-launcher — o que a máquina realmente tem\n")

    print("  \033[2mQual arquivo .desktop é de qual programa\033[0m")
    by_name = {}
    for _key, _title, entries in catalog_obj.sections:
        for entry in entries:
            by_name.setdefault((entry["category"], entry["name"]), entry)

    steam_entry = by_name.get(("gaming", "Steam"))
    check("a entrada Steam existe no catálogo", steam_entry is not None)
    if steam_entry:
        info = catalog_obj.find_appinfo(steam_entry)
        found = info.get_id() if info else None
        check(
            "Steam resolve para steam.desktop, não para um jogo",
            found == "steam.desktop",
            f"resolveu para {found}",
        )
        command = module.Launcher._command_for(steam_entry, info)
        check(
            "o comando do Steam não carrega um jogo junto",
            bool(command) and "rungameid" not in command,
            str(command),
        )

    check(
        "`steam %U` é reconhecido como o próprio programa",
        module.Catalog._is_the_program(
            next(i for i in catalog_obj.appinfos if i.get_id() == "steam.desktop")
        ),
    )
    check(
        "`steam steam://rungameid/...` não é",
        not module.Catalog._is_the_program(
            next(i for i in catalog_obj.appinfos
                 if i.get_id() == "0000-hollow-knight.desktop")
        ),
    )

    print("\n  \033[2mO que já está instalado\033[0m")
    krita = by_name.get(("gaming", "Krita"))
    check(
        "Krita conta como instalado: o programa está no PATH",
        bool(krita and krita["installed"]),
    )
    discord = by_name.get(("gaming", "Discord"))
    check(
        "Discord como Flatpak conta como instalado",
        bool(discord and discord["installed"]),
    )
    blender = by_name.get(("gaming", "Blender"))
    check(
        "Blender, que não está em lugar nenhum, continua não instalado",
        bool(blender and not blender["installed"]),
    )
    kit = by_name.get(("gaming", "Kit Redes"))
    check(
        "um kit de vários pacotes não vira instalado por causa de um só",
        bool(kit and not kit["installed"]),
    )

    print("\n  \033[2mOs jogos que a máquina tem\033[0m")
    gaming = next(
        (entries for key, _t, entries in catalog_obj.sections if key == "gaming"), []
    )
    names = [e["name"] for e in gaming]
    check(
        "os jogos instalados vêm antes da loja",
        names[:2] == ["Celeste", "Hollow Knight"],
        str(names[:4]),
    )
    check(
        "o Steam não aparece duas vezes",
        names.count("Steam") == 1,
        str(names),
    )
    check(
        "o tile do jogo abre o jogo, não a loja",
        all(e.get("kind") == "app" for e in gaming[:2]),
    )
    hollow = next(e for e in gaming if e["name"] == "Hollow Knight")
    check(
        "e abre com o id do jogo",
        "rungameid/367520" in (module.Launcher._command_for(hollow, hollow["appinfo"]) or ""),
        str(module.Launcher._command_for(hollow, hollow["appinfo"])),
    )
    check(
        "o Krita, que não é jogo, fica fora",
        "Krita" not in names[:2],
    )

    print("\n  \033[2mCom que um jogo é embrulhado\033[0m")
    # Two wrappers, both only for games and both invisible: the discrete card
    # on a hybrid laptop, and gamemode - which puts the processor on the
    # performance governor for as long as the game is open and gives it back
    # the moment it closes.
    launcher = module.Launcher.__new__(module.Launcher)
    launcher._offload_gpu = False
    hollow = next(e for e in gaming if e["name"] == "Hollow Knight")
    firefox = next(e for _k, _t, ents in catalog_obj.sections for e in ents
                   if e["name"] == "Firefox")

    check(
        "sem gamemoderun instalado, nada é acrescentado",
        launcher._game_prefix(hollow, hollow["appinfo"], "hollow_knight") == "",
    )

    # With gamemoderun on PATH.
    write_stub(bins, "gamemoderun")
    check(
        "um jogo ganha o gamemoderun",
        launcher._game_prefix(hollow, hollow["appinfo"], "hollow_knight") == "gamemoderun ",
        repr(launcher._game_prefix(hollow, hollow["appinfo"], "hollow_knight")),
    )
    check(
        "e o que não é jogo não ganha nada",
        launcher._game_prefix(firefox, None, "firefox") == "",
        repr(launcher._game_prefix(firefox, None, "firefox")),
    )

    # And on a hybrid laptop, both, in the order that works: the offload
    # wrapper outside, since it is what chooses the card the game then runs on.
    launcher._offload_gpu = True
    check(
        "num notebook híbrido, os dois na ordem certa",
        launcher._game_prefix(hollow, hollow["appinfo"], "hollow_knight")
        == "ifos-gpu run gamemoderun ",
        repr(launcher._game_prefix(hollow, hollow["appinfo"], "hollow_knight")),
    )

    # ── A loja não é um jogo, e embrulhá-la quebrava as duas ─────────────────
    #  gamemoderun funciona por LD_PRELOAD, e o LD_PRELOAD é herdado por todo
    #  processo filho. O Steam e o Hydra rodam a interface deles dentro de um
    #  sandbox do Chromium - o steamwebhelper é CEF, o Hydra é Electron - e um
    #  sandbox do Chromium falha num preload que não consegue carregar. O
    #  cliente do Steam é de 32 bits, então sem o lib32-gamemode não há nem o
    #  que carregar, e o resultado é "Unexpected Transport Error (0x3008)" sem
    #  nada ali dentro falando em GameMode, em LD_PRELOAD ou no lançador.
    #
    #  `ifos-gpu run steam` funcionava; `ifos-gpu run gamemoderun steam` não.
    steam_entry = next(e for e in gaming if e["name"] == "Steam")
    check(
        "o Steam não ganha gamemoderun",
        "gamemoderun" not in launcher._game_prefix(steam_entry, None, "/usr/bin/steam"),
        repr(launcher._game_prefix(steam_entry, None, "/usr/bin/steam")),
    )
    check(
        "mas continua indo para a placa dedicada",
        launcher._game_prefix(steam_entry, None, "/usr/bin/steam") == "ifos-gpu run ",
        repr(launcher._game_prefix(steam_entry, None, "/usr/bin/steam")),
    )
    for store in ("steam", "/usr/bin/steam-runtime", "lutris", "heroic",
                  "hydralauncher", "bottles"):
        check(
            "reconhece %s como loja" % store,
            module.Launcher._is_storefront(store),
        )
    for game in ("hollow_knight", "/usr/games/celeste", "supertuxkart"):
        check(
            "e %s continua sendo jogo" % game,
            not module.Launcher._is_storefront(game),
        )
    check(
        "argumentos não confundem a checagem",
        module.Launcher._is_storefront("/usr/bin/steam -silent"),
    )
    check(
        "comando vazio não quebra",
        not module.Launcher._is_storefront("   "),
    )
    os.remove(os.path.join(bins, "gamemoderun"))

    print("\n  \033[2mTiles de sistema sem nada por trás\033[0m")
    check("um comando que existe passa", module.command_exists("sh -c true"))
    check(
        "um comando que não existe é recusado",
        not module.command_exists("programa-que-nao-existe --flag"),
    )
    check(
        "sudo é olhado através: o que importa é o segundo",
        not module.command_exists("sudo programa-que-nao-existe"),
    )
    check(
        "um caminho absoluto executável passa",
        module.command_exists(os.path.join(bins, "steam")),
    )
    check(
        "um caminho que não existe é recusado",
        not module.command_exists("/nao/existe/nada.sh"),
    )
    system = next(
        (entries for key, _t, entries in catalog_obj.sections if key == "sistema"), []
    )
    names = {e["name"] for e in system}
    check(
        "a seção Sistema não ficou vazia",
        bool(names),
        "nenhum tile de sistema sobreviveu ao filtro",
    )
    for tile in system:
        if not module.command_exists(tile["command"]):
            check(f"tile «{tile['name']}» tem comando válido", False, tile["command"])
            break
    else:
        check("todo tile de sistema tem um comando que existe", True)

    print("\n  \033[2mEm que seção o launcher abre\033[0m")
    # The section keys come from the catalog filenames and the names on screen
    # come from a table; "jogos" is the second, "gaming" the first, and every
    # caller types the one they can see.
    keys = [k for k, _t, _e in catalog_obj.sections]
    titles = [t for _k, t, _e in catalog_obj.sections]
    for asked, expected in (("jogos", "gaming"),
                            ("gaming", "gaming"),
                            ("Internet", "browsers"),
                            ("Sistema", "sistema")):
        index = module.Launcher.section_for(asked, keys, titles)
        landed = keys[index] if index is not None else None
        check(f"--category {asked} abre em {expected}", landed == expected, str(landed))
    check(
        "uma seção que não existe não muda nada",
        module.Launcher.section_for("nao-existe", keys, titles) is None,
    )

    print("\n  \033[2mProcura\033[0m")
    check("acento não atrapalha", module.fold("Vídeo") == module.fold("video"))
    check("maiúscula não atrapalha", module.fold("STEAM") == module.fold("steam"))

    print("\n  \033[2mUm programa barulhento não trava o launcher\033[0m")
    # stderr used to be a pipe nobody read from before the grace period. A
    # kernel pipe holds about 64KB; a program that writes more than that
    # before exiting blocks on its own write() and never gets to open a
    # window. poll() then reads "still running" forever, so the launcher
    # declared success and quit - leaving the program stuck, off-screen,
    # forever. NVIDIA's driver logs enough on startup to hit this every time;
    # a quieter driver mostly didn't, which is why this read as "an NVIDIA
    # problem" rather than a launcher bug.
    fake = module.Launcher.__new__(module.Launcher)
    scheduled = []
    quit_calls = []
    orig_timeout_add, orig_main_quit = module.GLib.timeout_add, module.Gtk.main_quit
    module.GLib.timeout_add = lambda _ms, fn, *args: scheduled.append((fn, args))
    module.Gtk.main_quit = lambda: quit_calls.append(True)
    fake.hide = fake.show = fake.present = lambda: None
    fake.notified = None
    fake.notify = lambda message: setattr(fake, "notified", message)
    try:
        noisy = "yes 'aviso do driver de vídeo' | head -c 200000 1>&2; exit 1"
        start = time.monotonic()
        fake.launch_watched("Programa de teste", noisy)
        elapsed = time.monotonic() - start
        check(
            "escrever bastante em stderr não bloqueia o Popen",
            elapsed < 1.0,
            f"{elapsed:.2f}s",
        )
        # Stand in for the GLib timeout: give the child a moment to actually
        # exit, then run the callback the way the main loop would.
        time.sleep(0.5)
        fn, args = scheduled[0]
        fn(*args)
        check(
            "a saída de um programa que falhou chega inteira, não travada",
            bool(fake.notified) and "aviso do driver de vídeo" in fake.notified,
            repr(fake.notified),
        )
        check(
            "e o launcher não se fecha achando que deu certo",
            not quit_calls,
        )
    finally:
        module.GLib.timeout_add = orig_timeout_add
        module.Gtk.main_quit = orig_main_quit

    shutil.rmtree(root, ignore_errors=True)

    print(f"\n  \033[1;32m{PASS} passaram\033[0m", end="")
    if FAIL:
        print(f", \033[1;31m{FAIL} falharam\033[0m", end="")
    print("\n")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
