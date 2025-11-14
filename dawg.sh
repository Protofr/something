#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

backup_dir="/var/backups/cp-final-$(date +%Y%m%d-%H%M%S)"
score=0
default_ext=(mp3 wav mp4 m4a jpg jpeg png mov ogg)
apt_cmd="apt"

c_reset() { echo -ne "\e[0m"; }
c_red()    { echo -ne "\e[31m"; }
c_green()  { echo -ne "\e[32m"; }
c_yellow() { echo -ne "\e[33m"; }
c_blue()   { echo -ne "\e[34m"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    c_red; echo "please run with sudo or as root"; c_reset
    exit 1
  fi
}

ensure_backup_dir() {
  mkdir -p "$backup_dir"
}

backup_item() {
  local path="$1"
  ensure_backup_dir
  if [ -e "$path" ]; then
    cp -a -- "$path" "$backup_dir/" || true
    echo "backed up $path -> $backup_dir/"
  fi
}

add_score() {
  local pts="$1"
  score=$((score + pts))
}

confirm() {
  local prompt="${1:-are you sure?}"
  read -r -p "$prompt [y/N]: " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

show_header() {
  c_blue
  echo "============================================================"
  printf "cyberpatriot tool - free points mode |  score: %s pts\n" "$score"
  echo "backup dir: $backup_dir"
  echo "============================================================"
  c_reset
}

pam_set_minlen_and_remember() {
  file="/etc/pam.d/common-password"
  if [ ! -f "$file" ]; then
    c_red; echo "$file not found"; c_reset
    return
  fi
  backup_item "$file"
  if grep -q "pam_unix.so" "$file"; then
    if grep -q "minlen=" "$file"; then
      sed -ri 's/minlen=[0-9]+/minlen=10/g' "$file" || true
    else
      sed -ri 's/(pam_unix\.so[^\\n]*)/\\1 minlen=10/' "$file" || true
    fi
    if grep -q "remember=" "$file"; then
      sed -ri 's/remember=[0-9]+/remember=3/g' "$file" || true
    else
      sed -ri 's/(pam_unix\.so[^\\n]*)/\\1 remember=3/' "$file" || true
    fi
    echo "pam common-password updated (minlen=10 remember=3)"
    add_score 3
  else
    c_yellow; echo "pam_unix.so line not found in $file"; c_reset
  fi
}

pam_remove_nullok() {
  file="/etc/pam.d/common-auth"
  if [ ! -f "$file" ]; then
    c_red; echo "$file not found"; c_reset
    return
  fi
  backup_item "$file"
  sed -ri 's/\bnullok\b//g' "$file" || true
  echo "removed nullok from $file (if present)"
  add_score 4
}

pam_configure_faillock() {
  mkdir -p /usr/share/pam-configs
  backup_item "/usr/share/pam-configs/faillock"
  cat > /usr/share/pam-configs/faillock <<'EOF'
Name: Lockout on failed logins
Default: yes
Priority: 0
Auth-Type: Primary
Auth:
    [default=die]    pam_faillock.so authfail
    sufficient       pam_faillock.so authsucc
EOF
  if command -v pam-auth-update >/dev/null 2>&1; then
    pam-auth-update --enable faillock --package || true
    echo "pam faillock configured (use pam-auth-update to finalize options if interactive needed)."
    add_score 4
  else
    echo "pam-auth-update not available; faillock fragment created in /usr/share/pam-configs"
  fi
}

enable_tcp_syncookies_and_aslr() {
  file="/etc/sysctl.conf"
  backup_item "$file"
  sed -i '/net.ipv4.tcp_syncookies/d' "$file" || true
  sed -i '/net.ipv4.ip_forward/d' "$file" || true
  sed -i '/kernel.randomize_va_space/d' "$file" || true
  echo 'net.ipv4.tcp_syncookies=1' >> "$file"
  echo 'net.ipv4.ip_forward=0' >> "$file"
  echo 'kernel.randomize_va_space=2' >> "$file"
  sysctl --system >/dev/null 2>&1 || true
  echo "tcp_syncookies enabled, ip_forward disabled, aslr set"
  add_score 4
}

disable_ssh_root_login() {
  file="/etc/ssh/sshd_config"
  if [ -f "$file" ]; then
    backup_item "$file"
    if grep -q "^PermitRootLogin" "$file"; then
      sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' "$file" || true
    else
      echo 'PermitRootLogin no' >> "$file"
    fi
    systemctl restart sshd || systemctl restart ssh || true
    echo "disabled ssh root login"
    add_score 6
  else
    c_yellow; echo "$file not found"; c_reset
  fi
}

fix_shadow_permissions() {
  file="/etc/shadow"
  if [ -f "$file" ]; then
    backup_item "$file"
    chmod 640 "$file" || true
    echo "set /etc/shadow perms to 640"
    add_score 5
  fi
}

apt_update_upgrade_full() {
  $apt_cmd update -y || true
  $apt_cmd upgrade -y || true
  $apt_cmd full-upgrade -y || true
  echo "apt update && apt upgrade && apt full-upgrade completed"
  add_score 6
}

purge_unwanted_packages_list() {
  pkgs=(hydra ophcrack freeciv telnetd telnet ftp vsftpd x11vnc tightvncserver realvnc netcat nmap wireshark)
  echo "checking for unwanted packages to purge (dry-run shows found ones)"
  found=()
  for p in "${pkgs[@]}"; do
    if dpkg -l 2>/dev/null | awk '{print $2}' | grep -qx "$p"; then
      found+=("$p")
    fi
  done
  if [ ${#found[@]} -eq 0 ]; then
    echo "no known unwanted packages found"
    return
  fi
  echo "detected packages: ${found[*]}"
  if confirm "purge detected packages?"; then
    for p in "${found[@]}"; do
      backup_item "/var/lib/dpkg/info/${p}.list" || true
      $apt_cmd purge -y "$p" || $apt_cmd remove -y "$p" || true
    done
    $apt_cmd autoremove -y || true
    echo "purged detected packages"
    add_score 6
  else
    echo "skipping purge"
  fi
}

free_points_mode() {
  show_header
  c_yellow; echo "free points mode: applies many safe fixes and scans"; c_reset
  cat <<EOF
this will:
 - enable ufw (allow ssh)
 - enable unattended-upgrades (apt automation)
 - run apt update && apt upgrade && apt full-upgrade -y
 - fix /etc/shadow perms
 - disable ssh root login
 - set sysctl defaults: tcp_syncookies=1, ip_forward=0, randomize_va_space=2
 - pam hardening (minlen, remember, remove nullok, faillock fragments)
 - purge common unwanted packages (optional)

you will be prompted once before making changes.
EOF
  if ! confirm "proceed with free points run?"; then echo "cancelled"; return; fi

  echo "configuring ufw..."
  ufw allow OpenSSH || ufw allow 22/tcp || true
  ufw --force enable || true
  add_score 6
  echo "ufw configured and enabled."

  echo "configuring unattended-upgrades..."
  mkdir -p /etc/apt/apt.conf.d
  backup_item "/etc/apt/apt.conf.d/10periodic"
  backup_item "/etc/apt/apt.conf.d/20auto-upgrades"
  echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/10periodic
  echo 'APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
  add_score 6
  echo "unattended-upgrades configured."

  echo "running apt update and upgrade..."
  apt_update_upgrade_full

  echo "fixing /etc/shadow permissions..."
  fix_shadow_permissions

  echo "disabling SSH root login..."
  disable_ssh_root_login

  echo "setting sysctl parameters..."
  enable_tcp_syncookies_and_aslr

  echo "applying PAM hardening (minlen, remember)..."
  pam_set_minlen_and_remember
  echo "removing nullok from PAM common-auth..."
  pam_remove_nullok
  echo "configuring PAM faillock..."
  pam_configure_faillock

  echo "checking for and purging unwanted packages..."
  purge_unwanted_packages_list

  c_green; echo "free points run complete. estimated score: $score"; c_reset
}

require_root
ensure_backup_dir
echo "starting cyberpatriot_tool_final - focused on 'free points' and PAM hardening"
free_points_mode
echo "exiting. final estimated score: $score"
exit 0
