# The `ifos` command — one entry point to everything the system adds.

function ifos --description 'IFOS control command'
    set -l green (set_color 00a86b)
    set -l light (set_color 7ed957)
    set -l dim   (set_color 6c8f80)
    set -l reset (set_color normal)

    switch "$argv[1]"
        case apps software loja
            ifos-software $argv[2..-1]
        case launcher menu
            ifos-launcher $argv[2..-1]
        case escola moodle
            ifos-launcher --category escola-online
        case jogos games
            ifos-launcher --category jogos
        case tema theme
            ifos-theme $argv[2..-1]
        case instalar install
            sudo install-ifos $argv[2..-1]
        case atalhos keys teclas
            less -R /usr/share/ifos/keybindings.txt
        case update atualizar
            ifos-update $argv[2..-1]
        case aur yay
            install-yay
        case info
            fastfetch
        case '' help ajuda -h --help
            echo ''
            echo -s $green '  IFOS' $reset ' — comandos'
            echo ''
            echo -s '   ' $light 'ifos apps      ' $reset $dim 'instalar programas, jogos e drivers' $reset
            echo -s '   ' $light 'ifos launcher  ' $reset $dim 'abrir o launcher em tela cheia' $reset
            echo -s '   ' $light 'ifos escola    ' $reset $dim 'Moodle e sistemas do IFMS' $reset
            echo -s '   ' $light 'ifos jogos     ' $reset $dim 'seção de jogos do launcher' $reset
            echo -s '   ' $light 'ifos tema      ' $reset $dim 'alternar tema (ifms | mocha | radiohead)' $reset
            echo -s '   ' $light 'ifos instalar  ' $reset $dim 'instalar o IFOS no computador' $reset
            echo -s '   ' $light 'ifos atalhos   ' $reset $dim 'lista de atalhos de teclado' $reset
            echo -s '   ' $light 'ifos update    ' $reset $dim 'atualizar o sistema e o próprio IFOS' $reset
            echo -s '   ' $light 'ifos aur       ' $reset $dim 'habilitar o AUR (instala o yay)' $reset
            echo -s '   ' $light 'ifos info      ' $reset $dim 'informações do sistema' $reset
            echo ''
        case '*'
            echo "ifos: comando desconhecido '$argv[1]' — tente 'ifos help'" >&2
            return 1
    end
end
