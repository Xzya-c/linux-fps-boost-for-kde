#!/bin/bash
set -euo pipefail
trap 'echo -e "\e[1;91m[HATA] Komut çalıştırılırken hata oluştu, işlem durduruldu.\e[0m"' ERR

BACKUP_DIR="$HOME/.config/fps_boost_backup_$(date +%Y%m%d%H%M%S)"
APT_SOURCES="/etc/apt/sources.list"
SYSCTL_FILE="/etc/sysctl.d/99-fpsai.conf"
ENV_FILE="$HOME/.config/environment.d/fps_boost_ai.conf"

log() { echo -e "\e[1;96m[AI]\e[0m $1"; }
ok() { echo -e "\e[1;92m[OK]\e[0m $1"; }
fail() { echo -e "\e[1;91m[FAIL]\e[0m $1"; }

backup_file() {
  local file=$1
  [[ -f "$file" ]] && mkdir -p "$BACKUP_DIR" && cp -v "$file" "$BACKUP_DIR"
}

add_my_repos() {
  log "Benim özel repo mirrorlarımı ekliyorum..."
  backup_file "$APT_SOURCES"

  # Kaynak listesini komple yedekle
  sudo cp -v "$APT_SOURCES" "${APT_SOURCES}.bak_$(date +%s)"

  # Örnek olarak benim ultra hızlı mirrorlarımı ekliyorum, Ubuntu 22.04 için
  sudo tee "$APT_SOURCES" > /dev/null <<EOF
deb http://mirror.pnl.gov/ubuntu jammy main restricted universe multiverse
deb http://mirror.pnl.gov/ubuntu jammy-updates main restricted universe multiverse
deb http://mirror.pnl.gov/ubuntu jammy-backports main restricted universe multiverse
deb http://mirror.pnl.gov/ubuntu jammy-security main restricted universe multiverse
EOF

  log "Repo güncelleniyor..."
  sudo apt clean
  sudo apt update -qq
  ok "Repo kaynakları güncellendi."
}

fix_broken_packages() {
  log "Bozuk paketleri kontrol edip tamir ediyorum..."
  sudo dpkg --configure -a
  sudo apt install -f -y
  sudo apt autoremove -y
  sudo apt clean
  ok "Paketler tamir edildi ve temizlendi."
}

install_essentials() {
  log "Gerekli paketlerin yüklü olduğunu kontrol ediyorum..."
  for pkg in cpufrequtils flatpak qdbus curl wget; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      log "$pkg yükleniyor..."
      sudo apt install -y "$pkg"
      ok "$pkg yüklendi."
    else
      ok "$pkg zaten yüklü."
    fi
  done
}

apply_kernel_settings() {
  log "Kernel ayarları uygulanıyor..."
  local sysctl_conf="kernel.sched_child_runs_first=1
kernel.sched_autogroup_enabled=1
vm.dirty_ratio=10
vm.dirty_background_ratio=5
vm.swappiness=10
vm.vfs_cache_pressure=50
kernel.sched_migration_cost_ns=5000000
kernel.sched_min_granularity_ns=10000000
kernel.sched_wakeup_granularity_ns=15000000"

  echo "$sysctl_conf" | sudo tee "$SYSCTL_FILE" > /dev/null
  sudo sysctl -p "$SYSCTL_FILE"
  ok "Kernel ayarları aktif."
}

apply_env_vars() {
  log "Ortam değişkenleri uygulanıyor..."
  mkdir -p "$(dirname "$ENV_FILE")"
  cat <<EOF > "$ENV_FILE"
vblank_mode=0
__GL_SYNC_TO_VBLANK=0
__GL_THREADED_OPTIMIZATIONS=1
__GL_YIELD=USLEEP
RADV_PERFTEST=aco
EOF
  ok "Ortam değişkenleri yüklendi."
}

optimize_cpu_disk_ram() {
  log "CPU ve disk scheduler performans ayarları uygulanıyor..."
  sudo cpufreq-set -r -g performance
  for dev in /sys/block/sd*/queue/scheduler; do
    echo none | sudo tee "$dev" > /dev/null
  done
  sync
  echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
  ok "CPU governor, disk scheduler ve RAM temizliği tamam."
}

fix_flatpak_steam() {
  log "Flatpak Steam için environment override ayarlanıyor..."
  flatpak override --user --env=vblank_mode=0 com.valvesoftware.Steam
  flatpak override --user --env=__GL_SYNC_TO_VBLANK=0 com.valvesoftware.Steam
  flatpak override --user --env=__GL_THREADED_OPTIMIZATIONS=1 com.valvesoftware.Steam
  ok "Flatpak Steam optimizasyonları yapıldı."
}

fix_desktop_files() {
  log ".desktop dosyalarını optimize ediyorum..."
  local count=0
  while IFS= read -r -d '' file; do
    if ! grep -q "Exec=env vblank_mode=0" "$file"; then
      sed -i 's|Exec=|Exec=env vblank_mode=0 __GL_SYNC_TO_VBLANK=0 __GL_THREADED_OPTIMIZATIONS=1 |g' "$file"
      ((count++))
    fi
  done < <(find ~/.local/share/applications -name "*.desktop" -print0)
  ok "$count adet .desktop dosyası optimize edildi."
}

backup_all() {
  log "Tüm önemli dosyalar yedekleniyor..."
  backup_file "$APT_SOURCES"
  backup_file "$SYSCTL_FILE"
  backup_file "$ENV_FILE"
  ok "Yedekleme tamamlandı."
}

restore_backup() {
  log "Yedekten geri yükleme başlıyor..."
  if [[ -d "$BACKUP_DIR" ]]; then
    cp -vr "$BACKUP_DIR"/* /
    ok "Yedekler geri yüklendi."
  else
    fail "Yedek bulunamadı."
  fi
}

main_menu() {
  clear
  echo -e "\e[1;92m███ FPS BOOSTER AI Kral Edition ███\e[0m"
  echo
  echo "1) 🚀 Boost'u Başlat"
  echo "2) 🔧 Paketleri Onar ve Güncelle"
  echo "3) 💾 Yedekle"
  echo "4) ↩️ Geri Al"
  echo "5) ❌ Çıkış"
  echo
  read -rp "Seçiminiz: " sec
  case $sec in
    1)
      add_my_repos
      fix_broken_packages
      install_essentials
      apply_kernel_settings
      apply_env_vars
      optimize_cpu_disk_ram
      fix_flatpak_steam
      fix_desktop_files
      log "Tüm ayarlar başarıyla uygulandı! 🚀"
      ;;
    2)
      fix_broken_packages
      ;;
    3)
      backup_all
      ;;
    4)
      restore_backup
      ;;
    5)
      echo "Çıkılıyor..."
      exit 0
      ;;
    *)
      echo "Geçersiz seçim."
      sleep 1
      main_menu
      ;;
  esac
}

main_menu
