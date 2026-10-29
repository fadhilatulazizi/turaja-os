#!/usr/bin/env bash
set -e

# ==============================================================================
# TURAJA OS - PRODUCTION READY BUILDER (GITHUB ACTIONS EDITION)
# Basis: Debian 12 (Bookworm LTS Stable) - 64 Bit | Target: RAM <= 2GB
# Powered by PT. Turaja Teknologi Indonesia
# ==============================================================================

WORK_DIR="/tmp/turaja_build"
OUTPUT_DIR="/tmp/output_iso"

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
cd "$WORK_DIR"

echo "=== [1/5] Membersihkan direktori kerja sebelumnya ==="
rm -rf "$WORK_DIR/live-build"
mkdir -p "$WORK_DIR/live-build"
cd "$WORK_DIR/live-build"

echo "=== [2/5] Memasang dependensi live-build ==="
apt-get update
apt-get install -y live-build debootstrap isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools dosfstools squashfs-tools

echo "=== [3/5] Mengonfigurasi parameter sistem (Dual Boot: BIOS & UEFI) ==="
lb config \
    --distribution bookworm \
    --archive-areas "main contrib non-free non-free-firmware" \
    --architectures amd64 \
    --linux-flavours amd64 \
    --binary-images iso-hybrid \
    --bootloader syslinux \
    --debian-installer live \
    --debian-installer-gui true \
    --bootappend-live "boot=live components quiet splash username=turaja hostname=turaja-kiosk autologin" \
    --image-name "TurajaOS-Debian12-x86_64" \
    --iso-application "Turaja OS Kiosk" \
    --iso-publisher "PT. Turaja Teknologi Indonesia" \
    --iso-volume "TURAJA_OS"

# ------------------------------------------------------------------------------
# DAFTAR PAKET MINIMAL (Performa RAM <= 2GB + Kiosk Hardening)
# ------------------------------------------------------------------------------
mkdir -p config/package-lists
cat << 'EOF' > config/package-lists/turaja.list.chroot
# Core Engine & System
live-boot
live-config
live-config-systemd
systemd-sysv
cron
sudo
curl
ufw
zram-tools

# Server Tampilan & Window Manager Ringan
xorg
openbox
nodm
tint2
feh
unclutter
zenity
libnotify-bin
dunst

# Browser Kiosk
chromium

# Driver Hardware, Kamera, Audio, Input USB
alsa-utils
pulseaudio
v4l-utils
firmware-linux-free

# Jaringan & Jam
network-manager
network-manager-gnome
systemd-timesyncd
EOF

# ------------------------------------------------------------------------------
# INJEKSI STRUKTUR FILE SISTEM & HARDENING
# ------------------------------------------------------------------------------
mkdir -p config/includes.chroot/etc/systemd
mkdir -p config/includes.chroot/etc/default
mkdir -p config/includes.chroot/etc/cron.d
mkdir -p config/includes.chroot/etc/modprobe.d
mkdir -p config/includes.chroot/etc/chromium/policies/managed
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/etc/skel/.config/openbox
mkdir -p config/includes.chroot/etc/skel/.config/tint2

# 1. HARDENING: Blokir Flashdisk/USB Storage (Barcode Scanner, Mouse, Keyboard, Cam tetap aktif)
cat << 'EOF' > config/includes.chroot/etc/modprobe.d/turaja-usb-storage.conf
blacklist usb-storage
blacklist uas
EOF

# 2. HARDENING: Abaikan Tombol Power, Suspend, Tutup Layar + Matikan TTY Konsol (Anti Ctrl+Alt+F1..F6)
cat << 'EOF' > config/includes.chroot/etc/systemd/logind.conf
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
NAutoVTs=0
ReserveVT=0
EOF

# 3. HARDENING: Kebijakan Browser Chromium (Anti-Inspect, Anti-Print, Anti-Buka File)
cat << 'EOF' > config/includes.chroot/etc/chromium/policies/managed/turaja-policy.json
{
  "DeveloperToolsAvailability": 2,
  "PrintingEnabled": false,
  "AllowFileSelectionDialogs": false,
  "DefaultSearchProviderEnabled": false,
  "PasswordManagerEnabled": false,
  "TranslateEnabled": false
}
EOF

# 4. Optimasi Memori ZRAM (Kompresi LZ4, alokasikan 50% RAM)
cat << 'EOF' > config/includes.chroot/etc/default/zramswap
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

# 5. Sinkronisasi Jam & Tanggal Otomatis (NTP Indonesia WIB)
cat << 'EOF' > config/includes.chroot/etc/systemd/timesyncd.conf
[Time]
NTP=id.pool.ntp.org time.google.com
FallbackNTP=0.debian.pool.ntp.org pool.ntp.org
EOF

# 6. Auto-Shutdown Jam 17:00 & Cache Cleaning Pukul 04:00 Subuh
cat << 'EOF' > config/includes.chroot/etc/cron.d/turaja-maintenance
0 17 * * 1-5 root /sbin/shutdown -h now
0 4 * * * turaja rm -rf /home/turaja/.cache/chromium/Default/Cache/* 2>/dev/null
0 4 * * * root sync && echo 3 > /proc/sys/vm/drop_caches
EOF

# 7. Autologin Display Manager (nodm)
cat << 'EOF' > config/includes.chroot/etc/default/nodm
NODM_ENABLED=true
NODM_USER=turaja
NODM_FIRST_VT=7
NODM_XSESSION=/etc/X11/Xsession
NODM_X_OPTIONS="-nolisten tcp"
EOF

# 8. Konfigurasi Panel Tint2 (Systray Wifi/LAN + Jam Real-Time Pojok Kanan Atas)
cat << 'EOF' > config/includes.chroot/etc/skel/.config/tint2/tint2rc
panel_items = TC
panel_position = top right horizontal
panel_size = 230 36
panel_margin = 8 8
panel_padding = 4 4 4
panel_background_id = 1
panel_layer = top
strut_policy = follow_size

rounded = 6
border_width = 1
background_color = #0b0f19 85
border_color = #38bdf8 60

systray_padding = 4 4 4
systray_sort = ascending
systray_icon_size = 20
systray_icon_as_icon = 1

time1_format = %H:%M:%S
time1_font = DejaVu Sans Bold 9
time1_color = #38bdf8

time2_format = %a, %d %b %Y
time2_font = DejaVu Sans 7
time2_color = #cbd5e1

clock_tooltip = %A, %d %B %Y
clock_padding = 4 2
clock_background_id = 0
EOF

# 9. Pemantau Status Koneksi Jaringan (Toast Notification)
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-netmon.sh
#!/bin/bash
WAS_ONLINE=1
while true; do
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        if [ $WAS_ONLINE -eq 0 ]; then
            notify-send -u normal "Koneksi Pulih" "Sistem online. Sinkronisasi data..."
            WAS_ONLINE=1
        fi
    else
        if [ $WAS_ONLINE -eq 1 ]; then
            notify-send -u critical "Internet Terputus" "Mode Offline aktif. Absensi tetap berjalan."
            WAS_ONLINE=0
        fi
    fi
    sleep 10
done
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-netmon.sh

# 10. Watchdog Browser (Auto Re-Open jika crash)
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-watchdog.sh
#!/bin/bash
sleep 15
while true; do
    if ! pgrep -x "chromium" > /dev/null; then
        /usr/local/bin/turaja-kiosk.sh &
    fi
    sleep 8
done
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-watchdog.sh

# 11. Menu Admin Tersembunyi (Ctrl + Alt + Shift + T)
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-admin.sh
#!/bin/bash
PASS=$(zenity --password --title="Turaja OS - Admin Access")
if [ "$PASS" != "turaja123" ]; then
    zenity --error --text="Password salah!"
    exit 1
fi

AKSI=$(zenity --list --title="Turaja OS Maintenance" \
    --column="Opsi" --column="Keterangan" \
    "URL" "Ubah Nama Instansi & Link Absensi" \
    "FLUSH" "Bersihkan Cache & Restart Browser" \
    "REBOOT" "Mulai Ulang Sistem" \
    "POWEROFF" "Matikan Sistem Sekarang" \
    "TERMINAL" "Buka Terminal Pemeliharaan")

case $AKSI in
    "URL")
        rm -f /home/turaja/.turaja_config
        killall chromium
        ;;
    "FLUSH")
        killall chromium
        rm -rf /home/turaja/.cache/chromium/*
        ;;
    "REBOOT")
        reboot
        ;;
    "POWEROFF")
        poweroff
        ;;
    "TERMINAL")
        x-terminal-emulator || xterm
        ;;
esac
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-admin.sh

# 12. Launcher Kiosk Utama
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-kiosk.sh
#!/bin/bash
CONFIG_FILE="/home/turaja/.turaja_config"

if [ ! -f "$CONFIG_FILE" ]; then
    DATA=$(zenity --forms --title="Turaja OS Setup" \
        --text="Konfigurasi Awal Sistem Absensi\nPowered By PT. Turaja Teknologi Indonesia" \
        --add-entry="Nama Instansi" \
        --add-entry="Link / URL Web Absensi" \
        --separator="|")

    if [ $? -ne 0 ] || [ -z "$DATA" ]; then
        INSTANSI="Instansi Default"
        URL_ABSEN="https://google.com"
    else
        INSTANSI=$(echo "$DATA" | cut -d'|' -f1)
        URL_ABSEN=$(echo "$DATA" | cut -d'|' -f2)
    fi

    echo "INSTANSI=\"$INSTANSI\"" > "$CONFIG_FILE"
    echo "URL_ABSEN=\"$URL_ABSEN\"" >> "$CONFIG_FILE"
fi

source "$CONFIG_FILE"

feh --bg-color '#0b0f19' &
unclutter -idle 3 -root &
dunst &
tint2 &
nm-applet &
/usr/local/bin/turaja-netmon.sh &
/usr/local/bin/turaja-watchdog.sh &

exec chromium \
    --app="$URL_ABSEN" \
    --start-maximized \
    --no-first-run \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --autoplay-policy=no-user-gesture-required \
    --use-fake-ui-for-media-stream \
    --disk-cache-size=104857600
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-kiosk.sh

# 13. Autostart Openbox & Hotkey Binding
cat << 'EOF' > config/includes.chroot/etc/skel/.config/openbox/autostart
/usr/local/bin/turaja-kiosk.sh &
EOF

cat << 'EOF' > config/includes.chroot/etc/skel/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <keyboard>
    <keybind key="C-A-S-t">
      <action name="Execute">
        <command>/usr/local/bin/turaja-admin.sh</command>
      </action>
    </keybind>
  </keyboard>
</openbox_config>
EOF

# ------------------------------------------------------------------------------
# HOOK: Hak Akses, Firewall, User
# ------------------------------------------------------------------------------
mkdir -p config/hooks/live
cat << 'EOF' > config/hooks/live/01-finalize-turaja.chroot
#!/sh
set -e

ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

if id "turaja" >/dev/null 2>&1; then
    usermod -a -G video,audio,netdev,dialout turaja
else
    useradd -m -s /bin/bash -G video,audio,netdev,dialout turaja
    echo "turaja:turaja" | chpasswd
fi

cp -r /etc/skel/. /home/turaja/
chown -R turaja:turaja /home/turaja

# HARDENING: Firewall UFW
ufw default deny incoming
ufw default allow outgoing
ufw allow out 53/udp
ufw allow out 80/tcp
ufw allow out 443/tcp
ufw allow out 123/udp
systemctl enable ufw

systemctl enable NetworkManager
systemctl enable systemd-timesyncd
systemctl enable cron
systemctl enable zramswap
EOF
chmod 755 config/hooks/live/01-finalize-turaja.chroot

echo "=== [4/5] Memulai kompilasi ISO... ==="
lb build

echo "=== [5/5] Menyimpan file ISO hasil build ==="
FINAL_ISO_NAME="TurajaOS-Debian12-x86_64.iso"
mv TurajaOS-Debian12-x86_64.hybrid.iso "$OUTPUT_DIR/$FINAL_ISO_NAME"
chmod 664 "$OUTPUT_DIR/$FINAL_ISO_NAME"

echo "=================================================================="
echo "SUKSES! Berkas ISO siap pakai tersimpan di:"
echo "$OUTPUT_DIR/$FINAL_ISO_NAME"
echo "=================================================================="
