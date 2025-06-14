#!/bin/bash
set -e

ENV_FILE="$HOME/.config/environment.d/fps_boost_ai.conf"
SYSCTL_FILE="/etc/sysctl.d/99-fpsai.conf"
LOG_FILE="$HOME/fps_boost_ai_error.log"
touch "$LOG_FILE"

log_step() {
  echo -e "\e[1;96m[AI]\e[0m $1"
}

error_log() {
  echo -e "\e[1;91m[HATA]\e[0m $1"
  echo "[HATA] $1" >> "$LOG_FILE"
}

info_log() {
  echo -e "\e[1;92m[OK]\e[0m $1"
  echo "[OK] $1" >> "$LOG_FILE"
}

run_cmd() {
  # Komut çalıştır, hata varsa handle_error çağır
  echo "[RUN] $*"
  "$@"
  local status=$?
  if [ $status -ne 0 ]; then
    error_log "Komut başarısız: $*"
    handle_error "$*"
  else
    info_log "Komut başarıyla çalıştı: $*"
  fi
  return $status
}

handle_error() {
  local cmd="$1"
  error_log "Hata tespit edildi: $cmd"

  # KDE compositing hatası
  if [[ "$cmd" == *kwin* ]]; then
    log_step "KWin compositing problemi tespit edildi, yeniden başlatılıyor..."
    run_cmd qdbus org.kde.KWin /Compositor suspend
    run_cmd qdbus org.kde.KWin /Compositor resume
    return
  fi

  # systemctl servis hatası
  if [[ "$cmd" == systemctl* ]]; then
    local svc=$(echo "$cmd" | awk '{print $2}')
    log_step "$svc servisi hatası, durum kontrolü ve restart deneniyor..."
    run_cmd systemctl status "$svc"
    run_cmd systemctl restart "$svc"
    return
  fi

  # Paket yöneticisi hatası
  if [[ "$cmd" =~ apt-get|dnf|pacman ]]; then
    log_step "Paket yöneticisi hatası, güncelleme ve yükseltme yapılıyor..."
    if command -v apt-get &>/dev/null; then run_cmd sudo apt-get update -y && run_cmd sudo apt-get upgrade -y; fi
    if command -v dnf &>/dev/null; then run_cmd sudo dnf update -y; fi
    if command -v pacman &>/dev/null; then run_cmd sudo pacman -Syu --noconfirm; fi
    return
  fi

  # Genel fallback
  error_log "Önerilen otomatik çözüm yok, elle müdahale gerekebilir."
}

restore() {
  log_step "Geri alma başlatılıyor..."
  [[ -f $ENV_FILE ]] && run_cmd rm "$ENV_FILE" && info_log "Ortam değişkenleri kaldırıldı."
  [[ -f $SYSCTL_FILE ]] && run_cmd sudo rm "$SYSCTL_FILE" && run_cmd sudo sysctl --system && info_log "Kernel ayarları sıfırlandı."

  if command -v cpufreq-set &>/dev/null; then
    run_cmd sudo cpufreq-set -r -g ondemand && info_log "CPU governor 'ondemand' yapıldı."
  fi

  for dev in /sys/block/sd*/queue/scheduler; do
    echo mq-deadline | sudo tee "$dev" > /dev/null
  done && info_log "Disk I/O sıfırlandı."

  run_cmd find ~/.local/share/applications -name "*.desktop" -exec sed -i 's|env vblank_mode=0 __GL_SYNC_TO_VBLANK=0 __GL_THREADED_OPTIMIZATIONS=1 ||g' {} \;
  info_log ".desktop dosyalar sıfırlandı."

  run_cmd flatpak override --user --reset com.valvesoftware.Steam &>/dev/null && info_log "Flatpak Steam override sıfırlandı."

  run_cmd qdbus org.kde.KWin /Compositor resume &>/dev/null && info_log "KWin kompozitör yeniden başlatıldı."

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
  run_cmd sudo sysctl -p "$SYSCTL_FILE" && info_log "Uygulanabilir kernel ayarları aktif."

  log_step "CPU performance moduna geçiliyor..."
  if ! command -v cpufreq-set &>/dev/null; then
    run_cmd sudo apt install -y cpufrequtils
  fi
  run_cmd sudo cpufreq-set -r -g performance && info_log "CPU performance modu aktif."

  log_step "Disk I/O scheduler optimize ediliyor..."
  for dev in /sys/block/sd*/queue/scheduler; do
    echo none | sudo tee "$dev" > /dev/null
  done && info_log "Disk I/O ayarlandı."

  log_step "RAM ve cache temizleniyor..."
  sync; echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
  info_log "RAM temizlendi."

  log_step ".desktop dosyaları optimize ediliyor..."
  run_cmd find ~/.local/share/applications -name "*.desktop" -exec sed -i 's|Exec=|Exec=env vblank_mode=0 __GL_SYNC_TO_VBLANK=0 __GL_THREADED_OPTIMIZATIONS=1 |g' {} \;
  info_log "Başlatıcılar güncellendi."

  log_step "Flatpak Steam override ayarlanıyor..."
  run_cmd flatpak override --user --env=vblank_mode=0 com.valvesoftware.Steam
  run_cmd flatpak override --user --env=__GL_SYNC_TO_VBLANK=0 com.valvesoftware.Steam
  run_cmd flatpak override --user --env=__GL_THREADED_OPTIMIZATIONS=1 com.valvesoftware.Steam
  info_log "Steam Flatpak override tamamlandı."

  log_step "KDE X11 için kompozitör devre dışı..."
  run_cmd qdbus org.kde.KWin /Compositor suspend &>/dev/null && info_log "KWin kapatıldı."

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
