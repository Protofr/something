#!/usr/bin/env bash
# cyberpatriot_tool_final.sh
# final simplified cyberpatriot helper script
# - numbers-only menus
# - clean user lists: admins (sudo) and authorized (uid >=1000 not in sudo)
# - prohibited-file finder: list then confirm delete (per-file or bulk)
# - free points mode: runs many safe fixes and full apt update + apt full-upgrade -y
# - installs and runs multiple malware tools: chkrootkit, rkhunter, lynis (full coverage)
# - pam hardening: minlen, remember, faillock, remove nullok
# - backups to /var/backups before editing or deleting
# - no external log files, simple plain bash, lower-case comments throughout
# - run with sudo/root: sudo ./cyberpatriot_tool_final.sh
# warning: this script will change system files and install packages. test in a vm if needed.

set -euo pipefail
IFS=$'\n\t'

# configuration
backup_dir="/var/backups/cp-final-$(date +%Y%m%d-%H%M%S)"
last_search_file="/tmp/cp_final_found_files.txt"
score=0
default_ext=(mp3 wav mp4 m4a jpg jpeg png mov ogg)
apt_cmd="apt"

# color helpers (optional, simple)
c_reset() { echo -ne "\e[0m"; }
c_red()    { echo -ne "\e[31m"; }
c_green()  { echo -ne "\e[32m"; }
c_yellow() { echo -ne "\e[33m"; }
c_blue()   { echo -ne "\e[34m"; }

# ensure running as root
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    c_red; echo "please run with sudo or as root"; c_reset
    exit 1
  fi
}

# create backup dir
ensure_backup_dir() {
  mkdir -p "$backup_dir"
}

# simple backup helper
backup_item() {
  local path="$1"
  ensure_backup_dir
  if [ -e "$path" ]; then
    cp -a -- "$path" "$backup_dir/" || true
    echo "backed up $path -> $backup_dir/"
  fi
}

# score helper
add_score() {
  local pts="$1"
  score=$((score + pts))
}

# simple confirmation helper
confirm() {
  local prompt="${1:-are you sure?}"
  read -r -p "$prompt [y/N]: " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# clean header
show_header() {
  c_blue
  echo "============================================================"
  printf "cyberpatriot tool - final  |  score: %s pts\n" "$score"
  echo "backup dir: $backup_dir"
  echo "============================================================"
  c_reset
}

# ---------- user & group manager (clean lists) ----------
list_admins_clean() {
  echo "=== admins (members of sudo group) ==="
  members="$(getent group sudo 2>/dev/null | awk -F: '{print $4}')"
  if [ -z "$members" ]; then
    echo "  (no explicit sudo members)"
  else
    echo "$members" | tr ',' '\n' | sed '/^$/d' | sed -e 's/^/  - /'
  fi
}

list_authorized_clean() {
  echo "=== authorized standard users (uid >= 1000 and not in sudo) ==="
  awk -F: '($3>=1000 && $1!="nobody"){print $1}' /etc/passwd | while read -r u; do
    if groups "$u" 2>/dev/null | grep -qw sudo; then
      continue
    fi
    echo "  - $u"
  done
}

user_manager_menu() {
  while true; do
    show_header
    echo "user & group manager"
    echo " 1) show clean lists (admins / authorized users)"
    echo " 2) add user"
    echo " 3) delete user (backup home)"
    echo " 4) add user to group"
    echo " 5) remove user from group"
    echo " 6) change user password"
    echo " 7) set user max password age (chage)"
    echo " 8) back to main menu"
    read -r -p "choose: " c
    case "$c" in
      1)
        list_admins_clean
        echo
        list_authorized_clean
        echo
        read -r -p "press enter to continue..."
        ;;
      2)
        read -r -p "enter new username: " newu
        if id "$newu" >/dev/null 2>&1; then
          c_yellow; echo "user exists: $newu"; c_reset
        else
          read -r -p "create home (default /home/$newu)? [Y/n]: " yn
          hn="/home/$newu"
          if [ "$yn" = "n" ] || [ "$yn" = "N" ]; then
            read -r -p "enter home path or press enter: " hn_in
            hn=${hn_in:-$hn}
          fi
          read -r -p "make sudoer? [y/N]: " adm
          backup_item "/etc/passwd"
          backup_item "/etc/group"
          adduser --home "$hn" --gecos "" "$newu"
          if [ "$adm" = "y" ] || [ "$adm" = "Y" ]; then
            usermod -aG sudo "$newu"
            echo "$newu added to sudo"
          fi
          echo "user $newu created"
        fi
        ;;
      3)
        read -r -p "enter username to delete: " delu
        if ! id "$delu" >/dev/null 2>&1; then
          c_red; echo "no such user: $delu"; c_reset
        else
          home_dir=$(getent passwd "$delu" | cut -d: -f6)
          echo "user: $delu  home: $home_dir"
          if confirm "delete $delu and backup home?"; then
            [ -n "$home_dir" ] && backup_item "$home_dir"
            backup_item "/etc/passwd"
            backup_item "/etc/group"
            deluser --remove-home "$delu" || userdel -r "$delu" || true
            add_score 4
            c_green; echo "deleted $delu"; c_reset
          else
            echo "cancelled"
          fi
        fi
        ;;
      4)
        read -r -p "enter username to add to group: " u
        if ! id "$u" >/dev/null 2>&1; then c_red; echo "no such user"; c_reset; continue; fi
        read -r -p "enter group to add to: " g
        if ! getent group "$g" >/dev/null 2>&1; then
          read -r -p "group not found - create it? [y/N]: " cg
          if [ "$cg" = "y" ] || [ "$cg" = "Y" ]; then
            addgroup "$g"
          else
            echo "cancelled"
            continue
          fi
        fi
        backup_item "/etc/group"
        gpasswd -a "$u" "$g"
        echo "added $u to $g"
        ;;
      5)
        read -r -p "enter username to remove from group: " u
        if ! id "$u" >/dev/null 2>&1; then c_red; echo "no such user"; c_reset; continue; fi
        read -r -p "enter group to remove from: " g
        if ! getent group "$g" >/dev/null 2>&1; then c_red; echo "no such group"; c_reset; continue; fi
        members=$(getent group "$g" | awk -F: '{print $4}')
        if ! echo "$members" | grep -qw "$u"; then
          echo "$u is not an explicit member of $g"
          continue
        fi
        backup_item "/etc/group"
        gpasswd -d "$u" "$g"
        echo "removed $u from $g"
        ;;
      6)
        read -r -p "enter username to change password: " u
        if ! id "$u" >/dev/null 2>&1; then c_red; echo "no such user"; c_reset; continue; fi
        passwd "$u"
        echo "password changed for $u"
        ;;
      7)
        read -r -p "enter username to set max password age (days, e.g. 90): " u
        if ! id "$u" >/dev/null 2>&1; then c_red; echo "no such user"; c_reset; continue; fi
        read -r -p "enter max days (e.g. 90): " days
        chage -M "$days" "$u"
        echo "set max password age for $u to $days days"
        ;;
      8) return ;;
      *)
        c_red; echo "invalid"; c_reset
        ;;
    esac
  done
}

# ---------- prohibited files finder & remover ----------
find_prohibited_defaults() {
  echo "searching filesystem for default prohibited extensions: ${default_ext[*]}"
  rm -f "$last_search_file" || true
  for ext in "${default_ext[@]}"; do
    # search excluding pseudo filesystems; xdev avoids crossing fs boundaries
    find / -xdev -type f -iname "*.${ext}" -print 2>/dev/null >> "$last_search_file" || true
  done
  echo "search complete. results saved to $last_search_file"
  echo "found $(wc -l < "$last_search_file" 2>/dev/null || echo 0) files"
}

find_prohibited_custom() {
  read -r -p "enter custom find pattern (e.g. '*.mp3' or '/home/*/*.mp4'): " pat
  if [ -z "$pat" ]; then echo "no pattern entered"; return; fi
  rm -f "$last_search_file" || true
  if [[ "$pat" == *"*"* || "$pat" == *"?"* ]]; then
    find / -xdev -type f -iname "$pat" -print 2>/dev/null >> "$last_search_file" || true
  else
    find / -xdev -type f -path "$pat" -print 2>/dev/null >> "$last_search_file" || true
  fi
  echo "search complete. results saved to $last_search_file"
  echo "found $(wc -l < "$last_search_file" 2>/dev/null || echo 0) files"
}

preview_last_search() {
  if [ ! -s "$last_search_file" ]; then
    c_yellow; echo "no results to preview"; c_reset; return; fi
  echo "previewing first 200 results:"
  nl -ba "$last_search_file" | sed -n '1,200p'
}

delete_from_last_search() {
  if [ ! -s "$last_search_file" ]; then
    c_yellow; echo "no search results to delete"; c_reset; return; fi
  echo "choose deletion mode:"
  echo " 1) interactive per-file"
  echo " 2) bulk delete all (will backup first)"
  echo " 3) cancel"
  read -r -p "choose: " dopt
  case "$dopt" in
    1)
      while IFS= read -r f; do
        echo "file: $f"
        if confirm "delete this file?"; then
          backup_item "$f"
          rm -f -- "$f" || true
          echo "deleted $f"
          add_score 2
        else
          echo "skipped"
        fi
      done < "$last_search_file"
      ;;
    2)
      echo "bulk delete - backing up files first..."
      read -r -p "are you absolutely sure? [type YES to confirm]: " con
      if [ "$con" = "YES" ]; then
        while IFS= read -r f; do
          backup_item "$f"
        done < "$last_search_file"
        while IFS= read -r f; do
          rm -f -- "$f" || true
        done < "$last_search_file"
        echo "bulk delete complete"
        add_score 4
      else
        echo "bulk delete cancelled"
      fi
      ;;
    3) echo "cancelled" ;;
    *) c_red; echo "invalid"; c_reset ;;
  esac
}

files_menu() {
  while true; do
    show_header
    echo "prohibited files & media"
    echo " 1) find default prohibited files"
    echo " 2) find custom pattern"
    echo " 3) preview last search"
    echo " 4) delete from last search (interactive or bulk)"
    echo " 5) back to main menu"
    read -r -p "choose: " fch
    case "$fch" in
      1) find_prohibited_defaults ;;
      2) find_prohibited_custom ;;
      3) preview_last_search ;;
      4) delete_from_last_search ;;
      5) return ;;
      *) c_red; echo "invalid"; c_reset ;;
    esac
  done
}

# ---------- pam hardening helpers ----------
pam_set_minlen_and_remember() {
  # set pam minimum length and remember value in /etc/pam.d/common-password
  file="/etc/pam.d/common-password"
  if [ ! -f "$file" ]; then
    c_red; echo "$file not found"; c_reset
    return
  fi
  backup_item "$file"
  # ensure pam_unix.so line contains minlen=10 and remember=3
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
  sed -ri 's/\\bnullok\\b//g' "$file" || true
  echo "removed nullok from $file (if present)"
  add_score 4
}

pam_configure_faillock() {
  # create pam-configs fragments for faillock and run pam-auth-update
  mkdir -p /usr/share/pam-configs
  backup_item "/usr/share/pam-configs/faillock"
  cat > /usr/share/pam-configs/faillock <<'EOF'
Name: Lockout on failed logins
Default: no
Priority: 0
Auth-Type: Primary
Auth:
    [default=die]    pam_faillock.so authfail
    sufficient       pam_faillock.so authsucc
EOF
  cat > /usr/share/pam-configs/faillock_reset <<'EOF'
Name: Reset lockout on success
Default: no
Priority: 0
Auth-Type: Additional
Auth:
    required      pam_faillock.so authsucc
EOF
  cat > /usr/share/pam-configs/faillock_notify <<'EOF'
Name: Notify on failed login attempts
Default: no
Priority: 1024
Auth-Type: Primary
Auth:
    requisite      pam_faillock.so preauth
EOF
  # update pam config
  if command -v pam-auth-update >/dev/null 2>&1; then
    pam-auth-update --package || true
    echo "pam faillock configured (use pam-auth-update to finalize options if interactive needed)."
    add_score 4
  else
    echo "pam-auth-update not available; files created in /usr/share/pam-configs"
  fi
}

# ---------- sysctl & ssh helpers ----------
enable_tcp_syncookies_and_aslr() {
  file="/etc/sysctl.conf"
  backup_item "$file"
  # remove existing lines to avoid duplicates
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

# ---------- package & service helpers ----------
apt_update_upgrade_full() {
  # update, upgrade, full-upgrade
  $apt_cmd update -y || true
  $apt_cmd upgrade -y || true
  $apt_cmd full-upgrade -y || true
  echo "apt update && apt upgrade && apt full-upgrade completed"
  add_score 6
}

purge_unwanted_packages_list() {
  # common unwanted packages often present in cyberpatriot images
  pkgs=(hydra ophcrack freeciv telnetd telnet ftp vsftpd x11vnc tightvncserver realvnc rkhunter netcat nmap wireshark)
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

disable_and_stop_service() {
  read -r -p "enter service name to disable/stop (e.g. nginx): " svc
  if systemctl list-units --type=service --all | grep -q "$svc"; then
    backup_item "/etc/systemd/system/$svc.service" || true
    systemctl disable --now "$svc" || true
    echo "service $svc disabled and stopped (if present)"
    add_score 4
  else
    echo "service $svc not found"
  fi
}

# ---------- full malware checker (multi-tool) ----------
install_malware_tools_and_run() {
  echo "installing and running full malware toolset: chkrootkit, rkhunter, lynis"
  # update first
  $apt_cmd update -y || true
  # install chkrootkit, rkhunter, lynis
  $apt_cmd install -y chkrootkit rkhunter lynis || true

  # run chkrootkit
  echo "running chkrootkit..."
  chkrootkit 2>/dev/null || chkrootkit || true

  # run rkhunter: update and check
  echo "updating and running rkhunter..."
  rkhunter --update || true
  rkhunter --propupd || true  # build properties DB (may warn)
  rkhunter --checkall --sk --nolog || rkhunter --checkall || true

  # run lynis quick (audit system)
  echo "running lynis system audit (this may take a few minutes)..."
  lynis audit system || true

  echo "malware toolset completed (review output above for results)."
  add_score 10
}

# ---------- free points aggregated function ----------
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
 - install and run full malware tools (chkrootkit, rkhunter, lynis)
 - run quick scans and produce findings interactively
you will be prompted once before making changes.
EOF
  if ! confirm "proceed with free points run?"; then echo "cancelled"; return; fi

  # enable ufw (allow ssh)
  ufw allow OpenSSH || ufw allow 22 || true
  ufw --force enable || true
  add_score 6

  # enable unattended upgrades (periodic)
  mkdir -p /etc/apt/apt.conf.d
  backup_item "/etc/apt/apt.conf.d/20auto-upgrades"
  echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/10periodic
  echo 'APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
  add_score 6

  # apt full update & upgrade
  apt_update_upgrade_full

  # fix shadow perms
  fix_shadow_permissions

  # disable ssh root
  disable_ssh_root_login

  # sysctl settings
  enable_tcp_syncookies_and_aslr

  # pam hardening
  pam_set_minlen_and_remember
  pam_remove_nullok
  pam_configure_faillock

  # purge unwanted packages
  purge_unwanted_packages_list

  # install and run malware tools
  install_malware_tools_and_run

  c_green; echo "free points run complete. estimated score: $score"; c_reset
  read -r -p "press enter to continue..."
}

# ---------- quick audit & utilities ----------
quick_audit() {
  show_header
  echo "quick audit: listening sockets, active processes, ufw status, /etc/shadow perms"
  ss -tlnp 2>/dev/null || true
  ps -ef | head -n 40
  ufw status || true
  ls -l /etc/shadow || true
  read -r -p "press enter to continue..."
}

utilities_menu() {
  while true; do
    show_header
    echo "utilities"
    echo " 1) show score"
    echo " 2) show backup dir contents"
    echo " 3) restore a file from backup (interactive)"
    echo " 4) back to main menu"
    read -r -p "choose: " u
    case "$u" in
      1) echo "score: $score"; read -r -p "enter to continue..." ;;
      2) ls -lah "$backup_dir" || echo "(no backups yet)"; read -r -p "enter to continue..." ;;
      3)
        echo "available backups:"
        ls -lah "$backup_dir"
        read -r -p "enter filename from backup dir to restore (exact name): " fname
        if [ -z "$fname" ]; then echo "cancelled"; else
          if [ -e "$backup_dir/$fname" ]; then
            read -r -p "restore $fname to original path? you must specify full target path: " target
            if [ -z "$target" ]; then echo "target not provided, cancelled"; else
              cp -a -- "$backup_dir/$fname" "$target"
              echo "restored $backup_dir/$fname to $target"
            fi
          else
            echo "backup file not found"
          fi
        fi
        ;;
      4) return ;;
      *) c_red; echo "invalid"; c_reset ;;
    esac
  done
}

# ---------- main menu ----------
main_menu() {
  while true; do
    show_header
    echo "main menu"
    echo " 1) free points (safe automated fixes + full upgrade + malware tools)"
    echo " 2) user & group manager"
    echo " 3) prohibited files & media"
    echo " 4) pam hardening tools (minlen, remember, faillock, nullok removal)"
    echo " 5) sysctl & ssh helpers (tcp_syncookies, aslr, disable root ssh)"
    echo " 6) package & service helpers (full apt upgrade, purge unwanted pkgs, disable service)"
    echo " 7) full malware checker (chkrootkit, rkhunter, lynis)"
    echo " 8) quick audit"
    echo " 9) utilities"
    echo " 10) exit"
    read -r -p "choose: " m
    case "$m" in
      1) free_points_mode ;;
      2) user_manager_menu ;;
      3) files_menu ;;
      4)
        pam_menu
        ;;
      5)
        ssh_sysctl_menu
        ;;
      6)
        package_service_menu
        ;;
      7) install_malware_tools_and_run ;;
      8) quick_audit ;;
      9) utilities_menu ;;
      10) echo "exiting. final estimated score: $score"; exit 0 ;;
      *) c_red; echo "invalid"; c_reset ;;
    esac
  done
}

# pam menu
pam_menu() {
  while true; do
    show_header
    echo "pam hardening"
    echo " 1) set pam minlen and remember (minlen=10 remember=3)"
    echo " 2) remove nullok from common-auth"
    echo " 3) configure faillock fragments + pam-auth-update"
    echo " 4) back"
    read -r -p "choose: " p
    case "$p" in
      1) pam_set_minlen_and_remember ;;
      2) pam_remove_nullok ;;
      3) pam_configure_faillock ;;
      4) return ;;
      *) c_red; echo "invalid"; c_reset ;;
    esac
  done
}

# ssh & sysctl menu
ssh_sysctl_menu() {
  while true; do
    show_header
    echo "ssh & sysctl helpers"
    echo " 1) enable tcp syncookies and aslr (sysctl)"
    echo " 2) disable ssh root login"
    echo " 3) fix /etc/shadow permissions"
    echo " 4) back"
    read -r -p "choose: " s
    case "$s" in
      1) enable_tcp_syncookies_and_aslr ;;
      2) disable_ssh_root_login ;;
      3) fix_shadow_permissions ;;
      4) return ;;
      *) c_red; echo "invalid"; c_reset ;;
    esac
  done
}

# package & service menu
package_service_menu() {
  while true; do
    show_header
    echo "packages & services"
    echo " 1) apt update && upgrade && full-upgrade -y"
    echo " 2) purge common unwanted packages"
    echo " 3) disable & stop a service"
    echo " 4) back"
    read -r -p "choose: " ps
    case "$ps" in
      1) apt_update_upgrade_full ;;
      2) purge_unwanted_packages_list ;;
      3) disable_and_stop_service ;;
      4) return ;;
      *) c_red; echo "invalid"; c_reset ;;
    esac
  done
}

# ---------------- startup ----------------
require_root
ensure_backup_dir
echo "starting cyberpatriot_tool_final"
main_menu
