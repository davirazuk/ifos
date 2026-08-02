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
""")
    write_desktop(apps, "0000-hollow-knight.desktop", """[Desktop Entry]
Type=Application
Name=Hollow Knight
Exec=steam steam://rungameid/367520
Icon=steam_icon_367520
""")
    write_desktop(apps, "0001-celeste.desktop", """[Desktop Entry]
Type=Application
Name=Celeste
Exec=steam steam://rungameid/504230
Icon=steam_icon_504230
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

    print("\n  \033[2mProcura\033[0m")
    check("acento não atrapalha", module.fold("Vídeo") == module.fold("video"))
    check("maiúscula não atrapalha", module.fold("STEAM") == module.fold("steam"))

    shutil.rmtree(root, ignore_errors=True)

    print(f"\n  \033[1;32m{PASS} passaram\033[0m", end="")
    if FAIL:
        print(f", \033[1;31m{FAIL} falharam\033[0m", end="")
    print("\n")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
