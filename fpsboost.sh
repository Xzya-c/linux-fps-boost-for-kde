#!/bin/bash
set -e

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
  read -p "$1 (e/h): " answer
  [[ "$answer" =~ ^[Ee]$ ]]
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
  info_log ".desktop dosyalar sıfırlandı."

  flatpak override --user --reset com.valvesoftware.Steam &>/dev/null && info_log "Flatpak Steam override sıfırlandı."

  qdbus org.kde.KWin /Compositor resume &>/dev/null && info_log "KWin kompozitör yeniden başlatıldı."

  info_log "Tüm değişiklikler geri alındı."
}

boost() {
  log_step "Sistem analizi yapılıyor..."

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
    KEY=$1
    VALUE=$2
    if [[ -e /proc/sys/$(echo "$KEY" | tr . /) ]]; then
      SYSCTL_TEMP+="$KEY = $VALUE"$'\n'
      info_log "$KEY uygulanacak."
    else
      SYSCTL_TEMP+="# $KEY = $VALUE  # Not available"$'\n'
      error_log "$KEY desteklenmiyor, yorum satırına alındı."
    fi
  }

  check_param "kernel.sched_child_runs_first" "1"
  check_param "kernel.sched_autogroup_enabled" "1"
  check_param "vm.dirty_ratio" "10"
  check_param "vm.dirty_background_ratio" "5"

  echo "$SYSCTL_TEMP" | sudo tee "$SYSCTL_FILE" > /dev/null
  sudo sysctl -p "$SYSCTL_FILE" && info_log "Uygulanabilir kernel ayarları aktif."

  log_step "CPU performance moduna geçiliyor..."
  if ! command -v cpufreq-set &>/dev/null; then
    sudo apt install -y cpufrequtils
  fi
  sudo cpufreq-set -r -g performance && info_log "CPU performance modu aktif."

  log_step "Disk I/O scheduler optimize ediliyor..."
  for dev in /sys/block/sd*/queue/scheduler; do
    echo none | sudo tee "$dev" > /dev/null
  done && info_log "Disk I/O ayarlandı."

  log_step "RAM ve cache temizleniyor..."
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

  log_step "KDE X11 için kompozitör devre dışı..."
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
  read -p "Seçiminiz: " sec
  case $sec in
    1) boost ;;
    2) restore ;;
    3) echo "Çıkılıyor..."; exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 1; main_menu ;;
  esac
}

main_menu
