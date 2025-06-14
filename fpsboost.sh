#!/bin/bash
set -euo pipefail
trap 'echo -e "\e[1;91m[HATA] Komut çalıştırılırken hata oluştu, işlem durduruldu.\e[0m"' ERR

ENV_FILE="$HOME/.config/environment.d/fps_boost_ai.conf"
SYSCTL_FILE="/etc/sysctl.d/99-fpsai.conf"

log_step() {
  echo -e "\e[1;96m[AI]\e[0m $1"
}

error_log() {
  echo -e "\e[1;91m[HATA]\e[0m $1"
}

info_log() {
  echo -e "\e[1;92m[OK]\e[0m $1"
}

ask() {
  read -rp "$1 (e/h): " answer
  [[ "$answer" =~ ^[Ee]$ ]]
}

add_my_repos() {
  log_step "Ultra hızlı repo kaynaklarım ekleniyor..."
  sudo cp -v /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%s)
  sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb http://mirror.pnl.gov/ubuntu jammy main restricted universe multiverse
deb http://mirror.pnl.gov/ubuntu jammy-updates main restricted universe multiverse
deb http://mirror.pnl.gov/ubuntu jammy-backports main restricted universe multiverse
deb http://mirror.pnl.gov/ubuntu jammy-security main restricted universe multiverse
EOF
  sudo apt clean
  sudo apt update -qq
  info_log "Repo kaynakları güncellendi."
}

fix_broken_packages() {
  log_step "Bozuk paketler kontrol ediliyor ve tamir ediliyor..."
  sudo dpkg --configure -a
  sudo apt install -f -y
  sudo apt autoremove -y
  sudo apt clean
  info_log "Paketler tamir edildi ve temizlendi."
}

install_essentials() {
  log_step "Gerekli paketler kontrol ediliyor ve yükleniyor..."
  for pkg in cpufrequtils flatpak qdbus curl wget; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      log_step "$pkg yükleniyor..."
      sudo apt install -y "$pkg"
      info_log "$pkg yüklendi."
    else
      info_log "$pkg zaten yüklü."
    fi
  done
}

restore() {
  log_step "Geri alma başlatılıyor..."
  [[ -f $ENV_FILE ]] && rm "$ENV_FILE" && info_log "Ortam değişkenleri kaldırıldı."
  [[ -f $SYSCTL_FILE ]] && sudo rm "$SYSCTL_FILE" && sudo sysctl --system && info_log "Kernel ayarları sıfırlandı."

  if command -v cpufreq-set &>/dev/null; then
    sudo cpufreq-set -r -g ondemand && info_log "CPU governor 'ondemand' yapıldı."
  fi

  for dev in /sys/block/sd*/queue/scheduler; do
    echo mq-deadline | sudo tee "$dev" > /dev/null
  done && info_log "Disk I/O sıfırlandı."

  find ~/.local/share/applications -name "*.desktop" -exec sed -i 's|env vblank_mode=0 __GL_SYNC_TO_VBLANK=0 __GL_THREADED_OPTIMIZATIONS=1 ||g' {} \;
  info_log ".desktop dosyaları sıfırlandı."

  flatpak override --user --reset com.valvesoftware.Steam &>/dev/null && info_log "Flatpak Steam override sıfırlandı."

  qdbus org.kde.KWin /Compositor resume &>/dev/null && info_log "KWin kompozitör yeniden başlatıldı."

  info_log "Tüm değişiklikler geri alındı."
}

boost() {
  add_my_repos
  fix_broken_packages
  install_essentials

  log_step "Ortam değişkenleri uygulanıyor..."
  mkdir -p "$(dirname "$ENV_FILE")"
  cat <<EOF > "$ENV_FILE"
vblank_mode=0
__GL_SYNC_TO_VBLANK=0
__GL_THREADED_OPTIMIZATIONS=1
__GL_YIELD=USLEEP
RADV_PERFTEST=aco
EOF
  info_log "Ortam değişkenleri yüklendi."

  log_step "Kernel scheduler optimizasyonu..."
  SYSCTL_TEMP=""
  check_param() {
    local KEY=$1
    local VALUE=$2
    if [[ -e /proc/sys/$(echo "$KEY" | tr . /) ]]; then
      SYSCTL_TEMP+="$KEY = $VALUE"$'\n'
      info_log "$KEY uygulanacak."
    else
      SYSCTL_TEMP+="# $KEY = $VALUE  # Desteklenmiyor"$'\n'
      error_log "$KEY desteklenmiyor, yorum satırına alındı."
    fi
  }

  check_param "kernel.sched_child_runs_first" "1"
  check_param "kernel.sched_autogroup_enabled" "1"
  check_param "vm.dirty_ratio" "10"
  check_param "vm.dirty_background_ratio" "5"

  echo "$SYSCTL_TEMP" | sudo tee "$SYSCTL_FILE" > /dev/null
  sudo sysctl -p "$SYSCTL_FILE" && info_log "Kernel ayarları aktif."

  log_step "CPU performans modu aktif ediliyor..."
  if ! command -v cpufreq-set &>/dev/null; then
    sudo apt install -y cpufrequtils
  fi
  sudo cpufreq-set -r -g performance && info_log "CPU performans modu aktif."

  log_step "Disk I/O scheduler optimize ediliyor..."
  for dev in /sys/block/sd*/queue/scheduler; do
    echo none | sudo tee "$dev" > /dev/null
  done && info_log "Disk I/O ayarlandı."

  log_step "RAM ve önbellek temizleniyor..."
  sync; echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
  info_log "RAM temizlendi."

  log_step ".desktop dosyaları optimize ediliyor..."
  find ~/.local/share/applications -name "*.desktop" -exec sed -i 's|Exec=|Exec=env vblank_mode=0 __GL_SYNC_TO_VBLANK=0 __GL_THREADED_OPTIMIZATIONS=1 |g' {} \;
  info_log "Başlatıcılar güncellendi."

  log_step "Flatpak Steam override ayarlanıyor..."
  flatpak override --user --env=vblank_mode=0 com.valvesoftware.Steam
  flatpak override --user --env=__GL_SYNC_TO_VBLANK=0 com.valvesoftware.Steam
  flatpak override --user --env=__GL_THREADED_OPTIMIZATIONS=1 com.valvesoftware.Steam
  info_log "Steam Flatpak override tamamlandı."

  log_step "KDE X11 için kompozitör devre dışı bırakılıyor..."
  qdbus org.kde.KWin /Compositor suspend &>/dev/null && info_log "KWin kapatıldı."

  info_log "🚀 Tüm boost işlemleri başarıyla tamamlandı."
}

main_menu() {
  clear
  echo -e "\e[1;92m███████╗██████╗ ███████╗    ██████╗ ██╗   ██╗ ██████╗  ██████╗ ███████╗████████╗\e[0m"
  echo -e "\e[1;92m██╔════╝██╔══██╗██╔════╝    ██╔══██╗██║   ██║██╔═══██╗██╔═══██╗██╔════╝╚══██╔══╝\e[0m"
  echo -e "\e[1;92m█████╗  ██████╔╝███████╗    ██████╔╝██║   ██║██║   ██║██║   ██║█████╗     ██║   \e[0m"
  echo -e "\e[1;92m██╔══╝  ██╔═══╝ ╚════██║    ██╔═══╝ ██║   ██║██║   ██║██║   ██║██╔══╝     ██║   \e[0m"
  echo -e "\e[1;92m███████╗██║     ███████║    ██║     ╚██████╔╝╚██████╔╝╚██████╔╝███████╗   ██║   \e[0m"
  echo -e "\e[1;92m╚══════╝╚═╝     ╚══════╝    ╚═╝      ╚═════╝  ╚═════╝  ╚═════╝ ╚══════╝   ╚═╝   \e[0m"
  echo
  echo "1) 🚀 FPS BOOST işlemlerini başlat"
  echo "2) ♻️  Geri Al (sıfırla)"
  echo "3) ❌ Çıkış"
  echo
  read -rp "Seçiminiz: " sec
  case $sec in
    1) boost ;;
    2) restore ;;
    3) echo "Çıkış yapılıyor..."; exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 1; main_menu ;;
  esac
}

main_menu
