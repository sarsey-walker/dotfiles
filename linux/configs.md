# Arch linux

## apps

- Foliate : ereader simples
- festival : text-to-speech 
- speak-ng : Tbm um text-to-speech

## Geral?

- xfce4 : Uma boa DE. Tive um probleminha com som, use `xfce4-mixer` para ajustar volume. Ele tá na AUR
- Tive problemas com fonts, tipo, emojis e caracteres chineses. Não chega a ser um problema por enquanto, mas é meio chato.(Resolvi mas n lembro como, quando tiver novamente vou anotar)
- **SWAP** é essencial!!! Assim ele não trava com Android studio!!!

### SWAP config

- Não é preciso adicionar swap na instalação, mas recomendo que o faça, e caso não faça, aqui as instruções para adicionar:
    - Como super usuário rode `fallocate -l 8G /swapfile` 
        - `fallocate` cria um arquivo de determinado tamanho
        - `-l 8G` tamanho que quero
        - `/swapfile` Nome do arquivo 
    - mude as permições dele ` chmod 600 /swapfile `
        ``` 
        ]# ls -l /swapfile 
        -rw------- 1 root root 8589934592 Feb 20 15:55 /swapfile
        ```
    - Criar a memória swap `mkswap /swapfile`
    - Ative ele para uso `swapon /swapfile `
- Mas assim que vc reiniciar a máquina ela vai ser desativada, então para ativar automaticamente edite `nano /etc/fstab `
- Adicione a linha `/swapfile       swap    swap    defaults        0 0`
- Pode ser ao final do arquivo, não vai fazer muita diferença(Aparentemente)
- E é isso, aproveite

## Install AUR apps

- clone os repos
- No arch linux pelo menos, precisa instalar o `base-devel` 
- run `makepkg -sci` ou `makepkg -si` (vc pode rodar `makepkg -h` para ver tds os comandos)
    - Não precisa rodar com sudo, ele vai pedir a senha 

- Para remomver basta rodar comando que remove qualquer outro pacote: `sudo pacman -Rns <nome_pacote>` 
