#!/usr/bin/bash

# Run this script after system and desktop are already installed

# Make sure systemd-homed is working, or else sudo will not work

systemctl status systemd-homed
echo "Be sure to start and enable systemd-homed (as root) or else sudo may not work properly"
echo "Also, reinstall pambase if necessary `pacman -S pambase`"
echo "Type any to continue..." ; read empty

## DOTFILES
cp ~/.bashrc ~/.bashrc.orig
cp ~/.bash_profile ~/.bash_profile.orig

# SSH-AGENT SERVICE
echo "Start the ssh-agent service..."
eval $(ssh-agent)
ls ~/.ssh/* ; echo "Add which key? "; read key_name
ssh-add ~/.ssh/"$key_name"


## SYNC PACMAN DBs
sudo pacman -Syy
sudo pacman -Syu kitty fish firefox

## PERSONAL DIRECTORIES AND RESOURCES
echo "Making personal subdirectories..."
mkdir tmp repos build 

## INSTALL YAY  ## Do this last because of intermittant errors with yay-git
echo "Installing yay: "
cd ~/build
git clone https://aur.archlinux.org/yay-git.git
cd yay-git
makepkg -si
cd

sleep 2

yay -S hyprland-git

sleep 2

# install ML4W or My Linux 4 Work, is a great DE-like experience out-of-the-box made by Stephan Raabe.
bash <(curl -s https://raw.githubusercontent.com/mylinuxforwork/dotfiles/main/setup-arch.sh)
