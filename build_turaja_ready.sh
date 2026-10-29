#!/usr/bin/env bash
set -e

# ==============================================================================
# TURAJA OS - ULTIMATE PRODUCTION BUILDER (ALL-IN-ONE KIOSK EDITION)
# Basis: Debian 12 (Bookworm LTS Stable) - 64 Bit | Target: RAM <= 2GB
# Powered by PT. Turaja Teknologi Indonesia
# ==============================================================================

WORK_DIR="/tmp/turaja_build"
OUTPUT_DIR="/tmp/output_iso"

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
rm -rf "$WORK_DIR/live-build"
mkdir -p "$WORK_DIR/live-build"
cd "$WORK_DIR/live-build"

echo "=== [1/4] Mengonfigurasi Parameter Debian 12 + USB Always-On ==="
lb config noauto \
    --mode debian \
    --distribution bookworm \
    --archive-areas "main contrib non-free non-free-firmware" \
    --architectures amd64 \
    --linux-flavours amd64 \
    --binary-images iso-hybrid \
    --bootappend-live "boot=live components quiet splash loglevel=0 vt.global_cursor_default=0 usbcore.autosuspend=-1 locales=id_ID.UTF-8 username=turaja hostname=turaja-kiosk autologin" \
    --iso-application "Turaja OS Kiosk" \
    --iso-publisher "PT. Turaja Teknologi Indonesia" \
    --iso-volume "TURAJA_OS"

# ------------------------------------------------------------------------------
# DAFTAR PAKET LENGKAP
# ------------------------------------------------------------------------------
mkdir -p config/package-lists
cat << 'EOF' > config/package-lists/turaja.list.chroot
live-boot
live-config
live-config-systemd
systemd-sysv
locales
locales-all
cron
sudo
curl
ufw
zram-tools
acpi
numlockx
usbutils
dbus-x11
policykit-1
polkitd
lxpolkit
xorg
x11-xserver-utils
openbox
nodm
tint2
feh
unclutter
zenity
libnotify-bin
dunst
chromium
alsa-utils
pulseaudio
v4l-utils
ffmpeg
firmware-linux-free
firmware-iwlwifi
firmware-realtek
firmware-atheros
network-manager
network-manager-gnome
wireless-tools
wpasupplicant
systemd-timesyncd
xterm
plymouth
plymouth-themes
imagemagick
fonts-dejavu
fonts-noto-color-emoji
papirus-icon-theme
EOF

# ------------------------------------------------------------------------------
# INJEKSI FILE KONFIGURASI, FITUR PINTAR & HARDENING
# ------------------------------------------------------------------------------
echo "=== [2/4] Menyuntikkan Fitur Kiosk, Offline Handler, Watchdog & Keamanan ==="
mkdir -p config/includes.chroot/etc/systemd
mkdir -p config/includes.chroot/etc/default
mkdir -p config/includes.chroot/etc/cron.d
mkdir -p config/includes.chroot/etc/modprobe.d
mkdir -p config/includes.chroot/etc/udev/rules.d
mkdir -p config/includes.chroot/etc/NetworkManager/conf.d
mkdir -p config/includes.chroot/etc/polkit-1/localauthority/50-local.d
mkdir -p config/includes.chroot/etc/chromium/policies/managed
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/usr/share/turaja
mkdir -p config/includes.chroot/etc/skel/.config/openbox
mkdir -p config/includes.chroot/etc/skel/.config/tint2

# 1. Pastikan NetworkManager Mengelola Semua Kartu Wi-Fi & Ethernet
cat << 'EOF' > config/includes.chroot/etc/NetworkManager/conf.d/10-globally-managed.conf
[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=no
EOF

# 2. Berikan Izin Penuh bagi User Turaja untuk Konek/Ganti Wi-Fi Tanpa Password Root
cat << 'EOF' > config/includes.chroot/etc/polkit-1/localauthority/50-local.d/10-network-manager.pkla
[Allow turaja to manage network]
Identity=unix-user:turaja;unix-group:netdev;unix-group:sudo
Action=org.freedesktop.NetworkManager.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

# 3. Blokir Flashdisk/USB Storage + Matikan Autosuspend untuk Barcode/Kamera USB
cat << 'EOF' > config/includes.chroot/etc/modprobe.d/turaja-usb-storage.conf
blacklist usb-storage
blacklist uas
EOF

cat << 'EOF' > config/includes.chroot/etc/udev/rules.d/50-turaja-usb-awake.rules
ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{power/autosuspend}="-1"
EOF

# 4. Matikan Tombol Power Fisik & Tutup Konsol TTY (Anti Ctrl+Alt+F1..F6)
cat << 'EOF' > config/includes.chroot/etc/systemd/logind.conf
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
NAutoVTs=0
ReserveVT=0
EOF

# 5. Kunci Browser Chromium + Auto-Allow Kamera & Mikrofon
cat << 'EOF' > config/includes.chroot/etc/chromium/policies/managed/turaja-policy.json
{
  "DeveloperToolsAvailability": 2,
  "PrintingEnabled": false,
  "AllowFileSelectionDialogs": false,
  "DefaultSearchProviderEnabled": false,
  "PasswordManagerEnabled": false,
  "TranslateEnabled": false,
  "BrowserSignin": 0,
  "IncognitoModeAvailability": 1,
  "BookmarkBarEnabled": false,
  "FullscreenAllowed": true,
  "VideoCaptureAllowed": true,
  "AudioCaptureAllowed": true,
  "VideoCaptureAllowedUrls": ["https://*", "http://*"],
  "AudioCaptureAllowedUrls": ["https://*", "http://*"]
}
EOF

# 6. Aktifkan ZRAM (Kompresi LZ4 untuk RAM <= 2GB)
cat << 'EOF' > config/includes.chroot/etc/default/zramswap
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

# 7. Server Jam Otomatis (NTP Indonesia)
cat << 'EOF' > config/includes.chroot/etc/systemd/timesyncd.conf
[Time]
NTP=id.pool.ntp.org time.google.com
FallbackNTP=0.debian.pool.ntp.org pool.ntp.org
EOF

# 8. Jadwal Auto-Shutdown Jam 17:00 & Bersih Cache Jam 04:00
cat << 'EOF' > config/includes.chroot/etc/cron.d/turaja-maintenance
0 17 * * 1-5 root /sbin/shutdown -h now
0 4 * * * turaja rm -rf /home/turaja/.cache/chromium/Default/Cache/* 2>/dev/null
0 4 * * * root sync && echo 3 > /proc/sys/vm/drop_caches
EOF

# 9. Konfigurasi Autologin ke Openbox via NODM
cat << 'EOF' > config/includes.chroot/etc/default/nodm
NODM_ENABLED=true
NODM_USER=turaja
NODM_FIRST_VT=7
NODM_XSESSION=/etc/X11/Xsession
NODM_X_OPTIONS="-nolisten tcp"
EOF

# 10. Halaman Tunggu Offline Pintar (Anti Layar Error Dinosaurus)
cat << 'EOF' > config/includes.chroot/usr/share/turaja/offline.html
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<title>TurajaOS - Menghubungkan Jaringan</title>
<style>
  body {
    margin: 0; padding: 0;
    background-color: #0b0f19; color: #f8fafc;
    font-family: 'DejaVu Sans', sans-serif;
    display: flex; flex-direction: column;
    justify-content: center; align-items: center;
    height: 100vh; text-align: center; user-select: none;
  }
  .spinner {
    width: 64px; height: 64px;
    border: 6px solid #1e293b; border-top-color: #38bdf8;
    border-radius: 50%; animation: spin 1s linear infinite;
    margin-bottom: 28px;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  h1 { color: #38bdf8; font-size: 28px; margin: 0 0 12px 0; }
  p { color: #94a3b8; font-size: 16px; max-width: 520px; line-height: 1.6; margin: 0 0 24px 0; }
  .badge {
    background: #1e293b; border: 1px solid #334155;
    padding: 10px 20px; border-radius: 8px;
    color: #cbd5e1; font-size: 14px;
  }
</style>
</head>
<body>
  <div class="spinner"></div>
  <h1>Menunggu Koneksi Jaringan...</h1>
  <p>Perangkat sedang terputus dari jaringan internet. Halaman absensi akan dimuat ulang secara otomatis begitu koneksi Wi-Fi atau kabel LAN kembali aktif.</p>
  <div class="badge">💡 Tips: Klik ikon <b>🌐</b> di pojok kanan atas layar atau tekan <b>Ctrl + Alt + W</b> untuk mengatur Wi-Fi.</div>
</body>
</html>
EOF

# 11. Script Pusat Kontrol Wi-Fi & Perangkat
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-wifi.sh
#!/bin/bash
PILIH=$(zenity --list --title="Pusat Kontrol Jaringan & Perangkat - TurajaOS" \
    --width=460 --height=280 \
    --text="Pilih pengaturan koneksi atau cek perangkat:" \
    --column="Kode" --column="Menu Pengaturan" \
    "WIFI" "🌐 Cari & Sambungkan Wi-Fi (Mode Cepat)" \
    "GUI" "⚙️ Pengaturan Lengkap Wi-Fi / IP LAN (Grafis)" \
    "STATUS" "⌨️🖱️ Cek Status Internet, IP, Suara & USB")

case $PILIH in
    "WIFI")
        xterm -fa 'DejaVu Sans Mono' -fs 11 -geometry 85x26 -title "Pilih Jaringan Wi-Fi (Gunakan Panah & Enter)" -e nmtui-connect
        ;;
    "GUI")
        nm-connection-editor
        ;;
    "STATUS")
        IP_ADDR=$(hostname -I | awk '{print $1}')
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            STATUS_NET="TERHUBUNG (ONLINE)"
        else
            STATUS_NET="TERPUTUS (OFFLINE)"
        fi
        BAT_INFO=$(acpi -b 2>/dev/null | head -n 1 || echo "Adaptor Langsung (Tanpa Baterai)")
        USB_DEV=$(lsusb | cut -d' ' -f7- | tr '\n' ' | ')
        zenity --info --width=440 --title="Informasi Sistem & Perangkat" \
            --text="<b>Status Internet:</b> $STATUS_NET\n<b>Alamat IP:</b> ${IP_ADDR:-Tidak Terdeteksi}\n<b>Status Daya:</b> $BAT_INFO\n<b>Perangkat USB Aktif:</b>\n$USB_DEV"
        ;;
esac
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-wifi.sh

# 12. Script Alat Tes Perangkat ("Hardware Self-Test")
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-selftest.sh
#!/bin/bash
TES=$(zenity --list --title="Hardware Self-Test - TurajaOS" \
    --width=450 --height=270 \
    --text="Pilih perangkat keras yang ingin diuji:" \
    --column="Kode" --column="Menu Pengujian" \
    "CAM" "📷 Tes Kamera / Webcam (Tutup dengan tombol Q / Esc)" \
    "AUDIO" "🔊 Tes Bunyi Speaker (Suara Beep / Wave)" \
    "SCANNER" "🔫 Tes Input Barcode / RFID Scanner")

case $TES in
    "CAM")
        if [ -e /dev/video0 ]; then
            ffplay -window_title "Tes Kamera TurajaOS (Tekan Q atau Esc untuk keluar)" -x 640 -y 480 /dev/video0
        else
            zenity --error --width=350 --text="Kamera (/dev/video0) tidak terdeteksi! Pastikan kabel webcam terpasang."
        fi
        ;;
    "AUDIO")
        amixer sset Master unmute >/dev/null 2>&1 || true
        amixer sset Master 85% >/dev/null 2>&1 || true
        speaker-test -t sine -f 800 -l 1 >/dev/null 2>&1 &
        PID_SPK=$!
        sleep 2
        kill -9 $PID_SPK 2>/dev/null || true
        zenity --info --width=350 --text="Pengujian speaker selesai (Volume disetel ke 85%)."
        ;;
    "SCANNER")
        HASIL=$(zenity --entry --width=400 --title="Tes Barcode / RFID Scanner" \
            --text="Arahkan kursor di kotak bawah ini, lalu scan kartu RFID atau Barcode Anda:")
        if [ -n "$HASIL" ]; then
            zenity --info --width=350 --title="Hasil Baca Scanner" --text="Scanner Berhasil Membaca Kode:\n\n<b>$HASIL</b>"
        fi
        ;;
esac
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-selftest.sh

# 13. Script Label Kiri & Kanan (Dengan Indikator Baterai + Jam Bahasa Indonesia)
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-brand-label.sh
#!/bin/bash
if [ -f "/home/turaja/.turaja_config" ]; then
    . "/home/turaja/.turaja_config"
    if [ -n "$INSTANSI" ] && [ "$INSTANSI" != "Instansi Default" ]; then
        echo "  TurajaOS  —  $INSTANSI"
        exit 0
    fi
fi
echo "  TurajaOS"
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-brand-label.sh

cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-status-icons.sh
#!/bin/bash
export LC_TIME=id_ID.UTF-8
TGL=$(date +"%H.%M, %d %B %Y")

# Cek status baterai jika dijalankan di laptop
BAT_STR=""
if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
    BAT_PATH=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1)
    if [ -n "$BAT_PATH" ]; then
        CAP=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "")
        STAT=$(cat "$BAT_PATH/status" 2>/dev/null || echo "")
        if [ -n "$CAP" ]; then
            if [ "$STAT" = "Charging" ] || [ "$STAT" = "Full" ]; then
                BAT_STR="⚡${CAP}% "
            else
                BAT_STR="🔋${CAP}% "
            fi
        fi
    fi
fi

echo "⌨️ 🖱️ 🌐 ${BAT_STR} $TGL  "
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-status-icons.sh

# 14. Konfigurasi Panel Tint2 (Top Bar Penuh)
cat << 'EOF' > config/includes.chroot/etc/skel/.config/tint2/tint2rc
# Layout: E (Brand Kiri) | F (Spacer Tengah) | S (Systray) | E (Ikon + Baterai + Jam Kanan)
panel_items = EFSE
panel_position = top center horizontal
panel_size = 100% 32
panel_margin = 0 0
panel_padding = 8 0 6
panel_background_id = 1
panel_layer = top
strut_policy = follow_size
wm_menu = 0

rounded = 0
border_width = 1
border_sides = B
background_color = #0b0f19 100
border_color = #1e293b 100

# Executor 1 (Kiri): Tulisan "TurajaOS"
execp = new
execp_command = /usr/local/bin/turaja-brand-label.sh
execp_interval = 10
execp_has_icon = 0
execp_cache_icon = 0
execp_font = DejaVu Sans Bold 10
execp_font_color = #38bdf8 100
execp_padding = 4 0
execp_background_id = 0
execp_lclick_command = /usr/local/bin/turaja-admin.sh

# System Tray (Ikon Sinyal nm-applet)
systray_padding = 6 0 4
systray_sort = ascending
systray_icon_size = 16
systray_icon_as_icon = 1

# Executor 2 (Kanan): "⌨️ 🖱️ 🌐 ⚡100%  05.00, 30 Oktober 2026"
execp = new
execp_command = /usr/local/bin/turaja-status-icons.sh
execp_interval = 1
execp_has_icon = 0
execp_cache_icon = 0
execp_font = DejaVu Sans Bold 9.5
execp_font_color = #f8fafc 100
execp_padding = 6 0
execp_background_id = 0
execp_lclick_command = /usr/local/bin/turaja-wifi.sh
execp_rclick_command = /usr/local/bin/turaja-wifi.sh
EOF

# 15. Script Pemantau Jaringan Otomatis (Auto-Switch Offline HTML <-> Web Absensi) + Alarm Baterai
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-netmon.sh
#!/bin/bash
WAS_ONLINE=1
MODE_OFFLINE_PAGE=0

while true; do
    # 1. Pantau Koneksi Internet & Alihkan Halaman Secara Otomatis
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        if [ $WAS_ONLINE -eq 0 ]; then
            notify-send -u normal "Koneksi Pulih" "Sistem kembali online. Memuat ulang halaman absensi..."
            WAS_ONLINE=1
            if [ $MODE_OFFLINE_PAGE -eq 1 ]; then
                MODE_OFFLINE_PAGE=0
                killall -9 chromium 2>/dev/null || true
            fi
        fi
    else
        if [ $WAS_ONLINE -eq 1 ]; then
            notify-send -u critical "Internet Terputus" "Mengalihkan ke mode tunggu koneksi..."
            WAS_ONLINE=0
            MODE_OFFLINE_PAGE=1
            killall -9 chromium 2>/dev/null || true
        fi
    fi

    # 2. Pantau Baterai Laptop (Peringatan jika charger terlepas & baterai < 30%)
    BAT_PATH=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1)
    if [ -n "$BAT_PATH" ]; then
        CAP=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo 100)
        STAT=$(cat "$BAT_PATH/status" 2>/dev/null || echo "Charging")
        if [ "$STAT" = "Discharging" ] && [ "$CAP" -le 30 ]; then
            notify-send -u critical "⚠️ PERINGATAN BATERAI LEMAH (${CAP}%)" "Kabel charger terlepas! Segera hubungkan adaptor listrik agar kiosk tidak mati."
            speaker-test -t sine -f 1000 -l 1 >/dev/null 2>&1 &
            sleep 1
            killall -9 speaker-test 2>/dev/null || true
        fi
    fi

    sleep 10
done
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-netmon.sh

# 16. Watchdog Browser + Anti-Freeze RAM (Khusus RAM <= 2GB)
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-watchdog.sh
#!/bin/bash
sleep 12
COUNTER=0
while true; do
    # Pastikan Chromium selalu menyala
    if ! pgrep -x "chromium" > /dev/null; then
        /usr/local/bin/turaja-browser-run.sh &
    fi

    # Cek penggunaan RAM setiap ~5 menit (60 x 5 detik)
    COUNTER=$((COUNTER + 1))
    if [ $COUNTER -ge 60 ]; then
        COUNTER=0
        MEM_PCT=$(free | awk '/Mem:/ {printf("%.0f", $3/$2 * 100)}')
        JAM=$(date +"%H")
        # Jika pemakaian RAM > 85% dan bukan jam sibuk masuk sekolah (06:00-08:00), segarkan browser
        if [ "$MEM_PCT" -ge 85 ] && [ "$JAM" != "06" ] && [ "$JAM" != "07" ]; then
            sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
            killall -9 chromium 2>/dev/null || true
        fi
    fi
    sleep 5
done
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-watchdog.sh

# 17. Panel Teknisi Rahasia (Ctrl + Alt + Shift + T)
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-admin.sh
#!/bin/bash
PASS=$(zenity --password --title="TurajaOS - Akses Teknisi")
if [ "$PASS" != "turaja123" ]; then
    zenity --error --text="Password salah!"
    exit 1
fi

AKSI=$(zenity --list --title="TurajaOS Maintenance & Diagnostics" \
    --width=480 --height=320 \
    --column="Opsi" --column="Keterangan" \
    "NETWORK" "🌐 Pengaturan Wi-Fi & Jaringan LAN" \
    "SELFTEST" "🛠️ Tes Kamera, Speaker & Barcode/RFID Scanner" \
    "URL" "🔗 Ubah Nama Instansi & Link Absensi" \
    "FLUSH" "🧹 Bersihkan Cache & Muat Ulang Browser" \
    "REBOOT" "🔄 Mulai Ulang Sistem (Reboot)" \
    "POWEROFF" "⏻ Matikan Perangkat Sekarang (Shutdown)" \
    "TERMINAL" "💻 Buka Terminal Teknisi")

case $AKSI in
    "NETWORK")
        /usr/local/bin/turaja-wifi.sh
        ;;
    "SELFTEST")
        /usr/local/bin/turaja-selftest.sh
        ;;
    "URL")
        rm -f /home/turaja/.turaja_config
        killall -9 chromium
        /usr/local/bin/turaja-kiosk.sh &
        ;;
    "FLUSH")
        killall -9 chromium
        rm -rf /home/turaja/.cache/chromium/*
        ;;
    "REBOOT")
        sudo reboot
        ;;
    "POWEROFF")
        sudo poweroff
        ;;
    "TERMINAL")
        xterm &
        ;;
esac
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-admin.sh

# 18. Script Eksekutor Browser Pintar (Otomatis pilih URL Absensi atau Halaman Offline)
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-browser-run.sh
#!/bin/bash
CONFIG_FILE="/home/turaja/.turaja_config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    URL_ABSEN="https://google.com"
fi

if [[ ! "$URL_ABSEN" =~ ^https?:// ]]; then
    URL_ABSEN="https://$URL_ABSEN"
fi

# Cek apakah internet aktif. Jika putus, tampilkan halaman tunggu offline lokal
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    TARGET_URL="$URL_ABSEN"
else
    TARGET_URL="file:///usr/share/turaja/offline.html"
fi

exec chromium \
    --no-sandbox \
    --app="$TARGET_URL" \
    --start-maximized \
    --no-first-run \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --disable-features=TranslateUI,OverscrollHistoryNavigation \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    --use-fake-ui-for-media-stream \
    --unsafely-treat-insecure-origin-as-secure="$URL_ABSEN" \
    --disk-cache-size=104857600
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-browser-run.sh

# 19. Script Launcher Kiosk Utama (Auto-Audio 85%, Auto-NumLock, Setup Awal)
cat << 'EOF' > config/includes.chroot/usr/local/bin/turaja-kiosk.sh
#!/bin/bash
export LANG=id_ID.UTF-8
export LC_TIME=id_ID.UTF-8
CONFIG_FILE="/home/turaja/.turaja_config"

# Matikan blank screen / sleep monitor
xset s off
xset -dpms
xset s noblank

# Aktifkan NumLock otomatis untuk Barcode / RFID Scanner
numlockx on 2>/dev/null || true

# Setel Volume Audio otomatis ke 85% (Unmute)
amixer sset Master unmute >/dev/null 2>&1 || true
amixer sset Master 85% >/dev/null 2>&1 || true
amixer sset PCM unmute >/dev/null 2>&1 || true
amixer sset PCM 85% >/dev/null 2>&1 || true

# Jalankan layanan background UI jika belum jalan
pgrep -x feh >/dev/null || feh --bg-color '#0b0f19' &
pgrep -x unclutter >/dev/null || unclutter -idle 3 -root &
pgrep -x dunst >/dev/null || dunst &
pgrep -x lxpolkit >/dev/null || lxpolkit &
pgrep -x tint2 >/dev/null || tint2 &
pgrep -x nm-applet >/dev/null || nm-applet &

# Jika belum ada internet saat baru nyala, tawarkan setting Wi-Fi dulu
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    if zenity --question --width=420 --title="Koneksi Internet Belum Aktif" \
        --text="Perangkat belum terhubung ke internet.\nApakah Anda ingin mengatur koneksi Wi-Fi / LAN sekarang?" \
        --ok-label="Atur Wi-Fi / LAN" --cancel-label="Lanjut Mode Offline"; then
        /usr/local/bin/turaja-wifi.sh
    fi
fi

# Setup konfigurasi instansi jika belum diatur
if [ ! -f "$CONFIG_FILE" ]; then
    DATA=$(zenity --forms --width=430 --title="TurajaOS Setup" \
        --text="Konfigurasi Awal Sistem Absensi\nPowered By PT. Turaja Teknologi Indonesia" \
        --add-entry="Nama Instansi (contoh: SMPN 1 Guntur)" \
        --add-entry="Link / URL Web Absensi (contoh: https://siskapro.my.id)" \
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

pgrep -f turaja-netmon.sh >/dev/null || /usr/local/bin/turaja-netmon.sh &
pgrep -f turaja-watchdog.sh >/dev/null || /usr/local/bin/turaja-watchdog.sh &

/usr/local/bin/turaja-browser-run.sh &
EOF
chmod 755 config/includes.chroot/usr/local/bin/turaja-kiosk.sh

# 20. Autostart Openbox & Penguncian Jendela Tanpa Bingkai
cat << 'EOF' > config/includes.chroot/etc/skel/.config/openbox/autostart
export LANG=id_ID.UTF-8
export LC_TIME=id_ID.UTF-8
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
fi
/usr/local/bin/turaja-kiosk.sh &
EOF

cat << 'EOF' > config/includes.chroot/etc/skel/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <keepBorder>no</keepBorder>
  </theme>
  <keyboard>
    <!-- Shortcut Admin Teknisi: Ctrl + Alt + Shift + T -->
    <keybind key="C-A-S-t">
      <action name="Execute">
        <command>/usr/local/bin/turaja-admin.sh</command>
      </action>
    </keybind>
    <!-- Shortcut Cepat Pengaturan Wi-Fi: Ctrl + Alt + W -->
    <keybind key="C-A-w">
      <action name="Execute">
        <command>/usr/local/bin/turaja-wifi.sh</command>
      </action>
    </keybind>
    <!-- Blokir Alt+F4 dan Ctrl+W agar browser tidak bisa ditutup user -->
    <keybind key="A-F4">
      <action name="Execute"><command>true</command></action>
    </keybind>
    <keybind key="C-w">
      <action name="Execute"><command>true</command></action>
    </keybind>
  </keyboard>
  <applications>
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
    <application name="zenity">
      <decor>yes</decor>
      <maximized>no</maximized>
      <layer>above</layer>
      <focus>yes</focus>
    </application>
    <application class="Nm-connection-editor">
      <decor>yes</decor>
      <maximized>no</maximized>
      <layer>above</layer>
      <focus>yes</focus>
    </application>
    <application name="xterm">
      <decor>yes</decor>
      <maximized>no</maximized>
      <layer>above</layer>
      <focus>yes</focus>
    </application>
    <application name="ffplay">
      <decor>yes</decor>
      <maximized>no</maximized>
      <layer>above</layer>
      <focus>yes</focus>
    </application>
  </applications>
</openbox_config>
EOF

# ------------------------------------------------------------------------------
# HOOK CHROOT (Locale Indonesia + Splashscreen Plymouth + User Permission)
# ------------------------------------------------------------------------------
mkdir -p config/hooks/live
cat << 'EOF' > config/hooks/live/01-finalize-turaja.hook.chroot
#!/bin/sh
set -e

# Set zona waktu WIB & Bahasa Indonesia
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
echo "Asia/Jakarta" > /etc/timezone
echo "id_ID.UTF-8 UTF-8" > /etc/locale.gen
locale-gen id_ID.UTF-8 || true
update-locale LANG=id_ID.UTF-8 LC_TIME=id_ID.UTF-8 || true

# Bersihkan konfigurasi ifupdown bawaan agar Ethernet dikelola penuh oleh NetworkManager
cat << 'NET_EOF' > /etc/network/interfaces
auto lo
iface lo inet loopback
NET_EOF

# Buat user turaja & izin akses sudo
if ! id "turaja" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G video,audio,netdev,dialout,sudo turaja
    echo "turaja:turaja" | chpasswd
fi

echo "turaja ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/turaja-power
chmod 440 /etc/sudoers.d/turaja-power

cp -r /etc/skel/. /home/turaja/
chown -R turaja:turaja /home/turaja

# ==============================================================================
# KONFIGURASI SPLASHSCREEN CUSTOM TURAJA OS (PLYMOUTH)
# ==============================================================================
THEME_DIR="/usr/share/plymouth/themes/turaja"
mkdir -p "$THEME_DIR"

convert -size 1366x768 xc:"#0b0f19" \
    -font "DejaVu-Sans-Bold" -pointsize 54 -fill "#38bdf8" -gravity center -annotate +0-30 "TURAJA OS" \
    -font "DejaVu-Sans" -pointsize 20 -fill "#cbd5e1" -gravity center -annotate +0+35 "Sistem Kiosk Absensi Terpadu" \
    -font "DejaVu-Sans" -pointsize 14 -fill "#64748b" -gravity south -annotate +0+40 "Powered by PT. Turaja Teknologi Indonesia" \
    "$THEME_DIR/background.png"

cat << 'PLY_CONF' > "$THEME_DIR/turaja.plymouth"
[Plymouth Theme]
Name=Turaja OS Splash
Description=Boot Splashscreen untuk Turaja OS
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/turaja
ScriptFile=/usr/share/plymouth/themes/turaja/turaja.script
PLY_CONF

cat << 'PLY_SCRIPT' > "$THEME_DIR/turaja.script"
Window.SetBackgroundTopColor(0.04, 0.06, 0.10);
Window.SetBackgroundBottomColor(0.04, 0.06, 0.10);

bg_image = Image("background.png");
resized_bg = bg_image.Scale(Window.GetWidth(), Window.GetHeight());
bg_sprite = Sprite(resized_bg);
bg_sprite.SetZ(-10000);
PLY_SCRIPT

plymouth-set-default-theme -R turaja || true
update-initramfs -u -k all || true

# Aktifkan service utama
systemctl enable NetworkManager.service || true
systemctl enable systemd-timesyncd.service || true
systemctl enable cron.service || true
systemctl enable zramswap.service || true
EOF
chmod 755 config/hooks/live/01-finalize-turaja.hook.chroot

echo "=== [3/4] Memulai Proses Build ISO ==="
lb build

echo "=== [4/4] Memindahkan File ISO ke Output ==="
FINAL_ISO_NAME="TurajaOS-Debian12-x86_64.iso"
ISO_FILE=$(ls *.iso 2>/dev/null | head -n 1)

if [ -n "$ISO_FILE" ]; then
    mv "$ISO_FILE" "$OUTPUT_DIR/$FINAL_ISO_NAME"
    chmod 664 "$OUTPUT_DIR/$FINAL_ISO_NAME"
    echo "BERHASIL: $OUTPUT_DIR/$FINAL_ISO_NAME"
else
    echo "ERROR: File ISO tidak ditemukan!"
    exit 1
fi
