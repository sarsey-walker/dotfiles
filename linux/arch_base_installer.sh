#!/usr/bin/env bash
# Considerar https://github.com/Thann/arcrypt as post install

# Constants for better maintainability
declare -r YES_PATTERN="^[yY]"
declare -r DEFAULT_LVM=0
declare -r DEFAULT_CRYPT=1

##########################################
######     GLOBAL PREFERENCES   ##########
##########################################

# Configuração básica
HOSTNAME="archie"
KEYBOARD="br"      # Alterar se necessário
default_keymap='br-abnt'             # set to your keymap name
TIME_ZONE="America/Sao_Paulo"
LOCALE="pt_BR.UTF-8"
FILESYSTEM="ext4"
SWAP_SIZE="1G"
ROOT_SIZE="10G"
HOME_SIZE=""       # O restante do espaço após as partições

IN_DEVICE="/dev/sda"  # Caminho do dispositivo de instalação
use_lvm=0   # return 0 if you want lvm
use_crypt=0 # return 0 if you want crypt
# Funções utilitárias

# Function to get user choice with default value
get_user_choice() {
    local prompt="$1"
    local default_value="$2"
    local response

    read -p "$prompt" response

    # Return default if empty response
    if [[ -z "$response" ]]; then
        echo "$default_value"
        return
    fi

    # Convert response to binary (0/1)
    [[ "$response" =~ $YES_PATTERN ]] && echo "0" || echo "1"
}

validate_device() {
    local device="$1"
    [[ -b "$device" ]] || error $LINENO "O dispositivo $device não existe ou não é válido."
}
# Verifica o modo de inicialização (UEFI ou BIOS)
efi_boot_mode() {
    [[ -d /sys/firmware/efi/efivars ]] && return 0 || return 1
}

# Solicita o caminho do disco
get_disk_path() {
    fdisk -l
    echo "Qual é o caminho do disco? (Ex: /dev/sda)"
    read -r IN_DEVICE
    validate_device "$IN_DEVICE"
}

# Verifica se a conexão de rede está funcionando
check_network_connection() {
##  check if reflector update is done...
	clear
	echo -e "\n\nWaiting until reflector has finished updating mirrorlist..."
	while true; do
		pgrep -x reflector &>/dev/null || break
		echo -n '.'
		sleep 2
	done
    echo "Testando conexão com a internet..."
    if ! ping -c 3 archlinux.org &>/dev/null; then
        error $LINENO "Não conectado à rede!" # Rastreia a linha onde o erro vai ocorrer
    fi
    echo "Conexão estabelecida com sucesso!"
}

# Exibe e sai com erro
# Função para rastrear a linha onde ocorreu o erro
error() {
    ERROR_LINE=$1  # A linha de erro é passada como argumento para a função
    ERROR_MSG=$2  # Mensagem de erro personalisada
    # track_error_line $1 $2
    return 1
}
# Add a logging function
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Set error handling
set -eE
# Improve error handling
error_handler() {
    local exit_code=$?
    local line_number=$ERROR_LINE
    if [ -z $line_number ]; then
        line_number=$1
    fi
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Command '${BASH_COMMAND}' failed at line $line_number. $ERROR_MSG"
        exit $exit_code
    fi
}

# trap 'error_handler $? $LINENO' ERR
trap 'error_handler ${LINENO}' ERR
# Monta a partição com verificação
mount_it() {
    local device=$1
    local mount_point=$2
    mount "$device" "$mount_point" || error $LINENO "Falha ao montar $device em $mount_point"
}

# Formata a partição
format_it() {
    local device=$1
    local fstype=$2
    mkfs."$fstype" "$device" || error $LINENO "Falha ao formatar $device com $fstype"
}

# Criação de partições para sistemas UEFI ou BIOS
### PARTITION AND FORMAT AND MOUNT
# Main partition creation function
create_partitions() {
    clear
	echo -e "\n\nPartitioning Hard Drive!! Press any key to continue... \n" ; read empty

    # Get LVM preference with default
    use_lvm=$(get_user_choice "Use LVM (Logical Volume Manager)? (Y/N) " "$DEFAULT_LVM")

    # Get encryption preference with default
    use_crypt=$(get_user_choice "Use Crypt? (Y/N) " "$DEFAULT_CRYPT")

    # Validate configuration
    if ! validate_partition_config "$use_lvm" "$use_crypt"; then
        read -p "Continue anyway? (Y/N) " continue_anyway
        [[ ! "$continue_anyway" =~ $YES_PATTERN ]] && return 1
    fi

	set_partition_name_and_size

	if use_lvm ; then
        lvm_create
    else
        non_lvm_create
    fi
}
validate_partition_config() {
    local use_lvm="$1"
    local use_crypt="$2"

    # Add validation logic here
    if [[ "$use_crypt" -eq 0 && "$use_lvm" -eq 1 ]]; then
        echo "Warning: Encryption without LVM might not be optimal"
        return 1
    fi
    return 0
}
set_partition_name_and_size(){
    # If IN_DEV is nvme then slices are p1, p2 etc
    if  efi_boot_mode ; then
        EFI_SIZE=512M
        if [[ $IN_DEVICE =~ nvme ]]; then
            EFI_DEVICE="${IN_DEVICE}p1"   # NOT for MBR systems
            ROOT_DEVICE="${IN_DEVICE}p2"  # only for non-LVM
            SWAP_DEVICE="${IN_DEVICE}p3"  # only for non-LVM
            HOME_DEVICE="${IN_DEVICE}p4"  # only for non-LVM
        else
            EFI_DEVICE="${IN_DEVICE}1"   # NOT for MBR systems
            ROOT_DEVICE="${IN_DEVICE}2"  # only for non-LVM
            SWAP_DEVICE="${IN_DEVICE}3"  # only for non-LVM
            HOME_DEVICE="${IN_DEVICE}4"  # only for non-LVM
        fi
    else
        BOOT_SIZE=512M
        # Any mobo with nvme probably is gonna be EFI I'm thinkin...
        # Probably no non-UEFI mobos with nvme drives
        DISKLABEL='MBR'
        unset EFI_DEVICE
        BOOT_DEVICE="${IN_DEVICE}1"
        BOOT_MTPT=/mnt/boot
        ROOT_DEVICE="${IN_DEVICE}2"
        SWAP_DEVICE="${IN_DEVICE}3"  # only for non-LVM
        HOME_DEVICE="${IN_DEVICE}4"  # only for non-LVM
    fi

    if use_lvm ; then
        # VOLUME GROUPS  (Probably should unset SWAP_DEVICE and HOME_DEVICE)
        PV_DEVICE="$ROOT_DEVICE"
        VOL_GROUP="arch_vg"
        LV_ROOT="ArchRoot"
        LV_HOME="ArchHome"
        LV_SWAP="ArchSwap"
    fi

}
format_device() {
    local device="$1"
    local fstype="$2"
    mkfs."$fstype" "$device" || error $LINENO "Não foi possível formatar $device como $fstype."
}

# ENCRYPT DISK WHEN POWER IS OFF
crypt_setup(){
    # Takes a disk partition as an argument
    # Give msg to user about purpose of encrypted physical volume
    cat <<END_OF_MSG

"You are about to encrypt a physical volume.  Your data will be stored in an encrypted
state when powered off.  Your files will only be protected while the system is powered off.
This could be very useful if your laptop gets stolen, for example."

END_OF_MSG
    read -p "Encrypting a disk partition. Please enter a memorable passphrase: " -s passphrase
    #echo -n "$passphrase" | cryptsetup -q luksFormat $1 -
    echo -n "$passphrase" | cryptsetup -q luksFormat --hash=sha512 --key-size=512 --cipher=aes-xts-plain64 --verify-passphrase $1 -

    cryptsetup luksOpen  $1 sda_crypt
    echo "Wiping every byte of device with zeros, could take a while..."
    dd if=/dev/zero of=/dev/mapper/sda_crypt bs=1M status=progress
    cryptsetup luksClose sda_crypt
    echo "Filling header of device with random data..."
    dd if=/dev/urandom of="$1" bs=512 count=20480 status=progress
}

non_lvm_create(){
    # We're just doing partitions, no LVM here
    clear
    if efi_boot_mode ; then
        sgdisk -Z "$IN_DEVICE"
        sgdisk -n 1::+"$EFI_SIZE" -t 1:ef00 -c 1:EFI "$IN_DEVICE"
        sgdisk -n 2::+"$ROOT_SIZE" -t 2:8300 -c 2:ROOT "$IN_DEVICE"
        sgdisk -n 3::+"$SWAP_SIZE" -t 3:8200 -c 3:SWAP "$IN_DEVICE"
        sgdisk -n 4 -c 4:HOME "$IN_DEVICE"

        # Format and mount slices for EFI
        format_it "$ROOT_DEVICE" "$FILESYSTEM"
        mount_it "$ROOT_DEVICE" /mnt
        mkfs.fat -F32 "$EFI_DEVICE"
        mkdir /mnt/boot && mkdir /mnt/boot/efi
        mount_it "$EFI_DEVICE" "$EFI_MTPT"
        format_it "$HOME_DEVICE" "$FILESYSTEM"
        mkdir /mnt/home
        mount_it "$HOME_DEVICE" /mnt/home
        mkswap "$SWAP_DEVICE" && swapon "$SWAP_DEVICE"
    else
        # For non-EFI. Eg. for MBR systems
cat > /tmp/sfdisk.cmd << EOF
$BOOT_DEVICE : start= 2048, size=+$BOOT_SIZE, type=83, bootable
$ROOT_DEVICE : size=+$ROOT_SIZE, type=83
$SWAP_DEVICE : size=+$SWAP_SIZE, type=82
$HOME_DEVICE : type=83
EOF


        # Using sfdisk because we're talking MBR disktable now...
        sfdisk "$IN_DEVICE" < /tmp/sfdisk.cmd

        # Format and mount slices for non-EFI
        format_it "$ROOT_DEVICE" "$FILESYSTEM"
        mount_it "$ROOT_DEVICE" /mnt
        format_it "$BOOT_DEVICE" "$FILESYSTEM"
        mkdir /mnt/boot
        mount_it "$BOOT_DEVICE" "$BOOT_MTPT"
        format_it "$HOME_DEVICE" "$FILESYSTEM"
        mkdir /mnt/home
        mount_it "$HOME_DEVICE" /mnt/home
        mkswap "$SWAP_DEVICE" && swapon "$SWAP_DEVICE"
    fi

    lsblk "$IN_DEVICE"
    echo "DONE. Type any key to continue..."; read empty
}

# PART OF LVM INSTALLATION
lvm_hooks(){
    clear
    echo "adding lvm2 to mkinitcpio hooks HOOKS=( base udev ... block lvm2 filesystems )"
    sleep 4
    pacman -Qi lvm2 || pacman -S lvm2
    sleep 6
    sed -i 's/^\(HOOKS=["(]base .*\) filesystems \(.*\)$/\1 lvm2 filesystems \2/g' /mnt/etc/mkinitcpio.conf
    arch-chroot /mnt mkinitcpio -P
    echo "Press any key to continue..."; read empty
}

# ONLY FOR LVM INSTALLATION
lvm_create(){
    clear
    sgdisk -Z "$IN_DEVICE"
    if efi_boot_mode ; then
        sgdisk -n 1::+"$EFI_SIZE" -t 1:ef00 -c 1:EFI "$IN_DEVICE"
        sgdisk -n 2 -t 2:8e00 -c 2:VOLGROUP "$IN_DEVICE"
        # Format
        mkfs.fat -F32 "$EFI_DEVICE"
    else
        #  # Create the slice for the Volume Group as first and only slice
    log "DEBUG" "Creating slice for the Volume Group as first and only slice"
    log "DEBUG" "DEVICE: $IN_DEVICE"
    log "DEBUG" "BOOT_DEVICE: $BOOT_DEVICE"

cat > /tmp/sfdisk.cmd << EOF
$BOOT_DEVICE : start= 2048, size=+$BOOT_SIZE, type=83, bootable
$ROOT_DEVICE : type=83
EOF
        # Using sfdisk because we're talking MBR disktable now...
        sfdisk "$IN_DEVICE" < /tmp/sfdisk.cmd
    fi


    # run cryptsetup on root device
    use_crypt && crypt_setup "$ROOT_DEVICE"

    # create the physical volumes
    pvcreate "$PV_DEVICE"
    # create the volume group
    vgcreate "$VOL_GROUP" "$PV_DEVICE"

    # You can extend with 'vgextend' to other devices too

    # create the volumes with specific size
    lvcreate -L "$ROOT_SIZE" "$VOL_GROUP" -n "$LV_ROOT"
    lvcreate -L "$SWAP_SIZE" "$VOL_GROUP" -n "$LV_SWAP"
    lvcreate -l 100%FREE  "$VOL_GROUP" -n "$LV_HOME"

    # Format SWAP
    mkswap /dev/"$VOL_GROUP"/"$LV_SWAP"
    swapon /dev/"$VOL_GROUP"/"$LV_SWAP"

    # insert the vol group module
    modprobe dm_mod
    # activate the vol group
    vgchange -ay

    # Format either the EFI_DEVICE or the BOOT_DEVICE
    if efi_boot_mode ; then
        mkfs.fat -F32 "$EFI_DEVICE"
    else
        format_it "$BOOT_DEVICE" "$FILESYSTEM"
    fi

    # Format the VG members
    format_it /dev/"$VOL_GROUP"/"$LV_ROOT" "$FILESYSTEM"
    format_it /dev/"$VOL_GROUP"/"$LV_HOME" "$FILESYSTEM"

    # mount the volumes
    mount_it /dev/"$VOL_GROUP"/"$LV_ROOT" /mnt
    mkdir /mnt/home
    mount_it /dev/"$VOL_GROUP"/"$LV_HOME" /mnt/home

    # Mount either the EFI or BOOT partition
    if efi_boot_mode ; then
        mkdir /mnt/boot && mkdir /mnt/boot/efi
        mount_it "$EFI_DEVICE" "$EFI_MTPT"
    else
        mkdir /mnt/boot
        mount_it "$BOOT_DEVICE" /mnt/boot
    fi

    lsblk
    echo "LVs created and mounted. Press any key."; read empty;
}


# Configuração do sistema
install_base_system() {
    clear
    BASE_SYSTEM=( base base-devel linux linux-firmware linux-headers dkms iwd networkmanager dhcpcd grub efibootmgr archlinux-keyring vim nano less man-db )
    echo "Instalando pacotes básicos: " "${BASE_SYSTEM[@]}"
    pacstrap -K /mnt "${BASE_SYSTEM[@]}"
    ## UPDATE mkinitrd HOOKS if using LVM
    use_lvm && arch-chroot /mnt pacman -S lvm2 -y
    use_lvm && lvm_hooks

    echo "Base do sistema instalada."
}

# Geração de fstab
generate_fstab() {
    genfstab -U /mnt > /mnt/etc/fstab
    cat /mnt/etc/fstab
    echo "Gerando fstab... Pressione qualquer tecla para continuar"; read empty
}

# Configurações de idioma e timezone
setup_locale_timezone() {
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIME_ZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc --utc
    arch-chroot /mnt date
    echo "Definindo timezone para $TIME_ZONE..."

    arch-chroot /mnt sed -i "s/#$LOCALE/$LOCALE/g" /etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=$LOCALE" > /mnt/etc/locale.conf
    export LANG="$LOCALE"
}

# Configurações de teclado e hostname
setup_keyboard_hostname() {
    echo "KEYMAP=$KEYBOARD" > /mnt/etc/vconsole.conf
    echo "$HOSTNAME" > /mnt/etc/hostname

cat > /mnt/etc/hosts <<HOSTS
127.0.0.1      localhost
::1            localhost
127.0.1.1      $HOSTNAME.localdomain     $HOSTNAME
HOSTS
    echo -e "/etc/hostname . . . \n"
    cat /mnt/etc/hostname
    echo -e "\n/etc/hosts . . .\n"
    cat /mnt/etc/hosts
    echo "Definindo hosts, hostname e configurações de teclado..."

    echo && echo -e "\n\nHere are /etc/hostname and /etc/hosts. Type any key to continue "; read empty
    ## SET PASSWD
    clear
    echo "Setting ROOT password..."
    arch-chroot /mnt passwd
}

## INSTALLING MORE ESSENTIALS
enabling_essentials(){
    clear
    echo && echo -e "\n\nEnabling dhcpcd, pambase, sshd and NetworkManager services..." && echo
    arch-chroot /mnt pacman -S openssh man-pages pambase git -y
    arch-chroot /mnt systemctl enable dhcpcd.service
    arch-chroot /mnt systemctl enable sshd.service
    arch-chroot /mnt systemctl enable NetworkManager.service
    arch-chroot /mnt systemctl enable systemd-homed
}

add_user(){
    ## ADD USER ACCT
    clear
    echo && echo -e "\n\nAdding sudo + user acct..."
    sleep 2
    arch-chroot /mnt pacman -S sudo bash-completion sshpass -y
    arch-chroot /mnt sed -i 's/# %wheel/%wheel/g' /etc/sudoers
    arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers
    # Caso usuariuo n isnira um nome por acidente
    while [[ -z "$sudo_user" ]]
    do
        echo && echo -e "\n\nPlease provide a username: "; read sudo_user
    done
    echo && echo -e "\n\nCreating $sudo_user and adding $sudo_user to sudoers..."
    arch-chroot /mnt useradd -m -G wheel "$sudo_user"
    echo && echo -e "\n\nPassword for $sudo_user?"
    arch-chroot /mnt passwd "$sudo_user"

}
# Configuração do GRUB
install_grub() {
    echo "Instalando e configurando o GRUB..."
    arch-chroot /mnt pacman -S grub os-prober -y
    if efi_boot_mode; then
        arch-chroot /mnt pacman -S efibootmgr -y

        [[ ! -d /mnt/boot/efi ]] && error $LINENO "Grub Install: no /mnt/boot/efi directory!!!"
        arch-chroot /mnt grub-install "$IN_DEVICE" --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi

        ## This next bit is for Ryzen systems with weird BIOS/EFI issues; --no-nvram and --removable might help
        [[ $? != 0 ]] && arch-chroot /mnt grub-install \
           "$IN_DEVICE" --target=x86_64-efi --bootloader-id=GRUB \
           --efi-directory=/boot/efi --no-nvram --removable
        echo -e "\n\nefi grub bootloader installed..."
    else
        arch-chroot /mnt grub-install "$IN_DEVICE"
        echo -e "\n\nmbr bootloader installed..."
    fi
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    echo "GRUB instalado e configurado."
}

# Função principal para iniciar o processo de instalação
main() {
	###  WELCOME
	clear
	echo -e "\n\n\nWelcome to the Fast ARCH Installer!"
	sleep 4

	### Change keymap if necessary
	if ! loadkeys "$default_keymap"; then
        error $LINENO "Erro ao carregar layout de teclado: $default_keymap" # Rastreia a linha onde o erro vai ocorrer
    fi
    # Checando a rede
    check_network_connection

    # Solicitar e validar disco de instalação
    # Obtenção do disco
    get_disk_path

    # Criação das partições
    create_partitions

    # Instalar sistema básico
    install_base_system

    # Gerar fstab
    generate_fstab

    # Configuração do sistema (timezone, locale)
    setup_locale_timezone

    # Configuração de teclado e hostname
    setup_keyboard_hostname

    # Essenciais
    enabling_essentials

    #add user
    add_user
    # Instalação do GRUB
    install_grub

    echo "Instalação concluída. Agora você pode reiniciar o sistema."

    echo -e "\n\nSystem should now be installed and ready to boot!!!"
    echo && echo -e "\nType shutdown -h now and remove Installation Media and then reboot"
    echo && echo

}

main
