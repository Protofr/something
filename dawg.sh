#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

backup_dir="/var/backups/cp-user-audit-$(date +%Y%m%d-%H%M%S)"

c_reset() { echo -ne "\e[0m"; }
c_red()   { echo -ne "\e[31m"; }
c_green() { echo -ne "\e[32m"; }
c_yellow(){ echo -ne "\e[33m"; }
c_blue()  { echo -ne "\e[34m"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    c_red; echo "run as root"; c_reset
    exit 1
  fi
}

backup_critical_files() {
  mkdir -p "$backup_dir"
  cp -a /etc/passwd /etc/shadow /etc/group "$backup_dir/"
  echo "Backups stored in $backup_dir"
}

show_header() {
  c_blue
  echo " CyberPatriot User Auditing Tool"
  c_reset
}

pause() {
  read -rp "Press ENTER to continue..."
}

confirm() {
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

audit_uid0_users() {
  c_yellow
  echo "UID 0 (root-level) users:"
  awk -F: '$3 == 0 {print " - " $1}' /etc/passwd
  c_reset
}

audit_login_users() {
  c_yellow
  echo "Users with login shells:"
  awk -F: '$7 !~ /(false|nologin)$/ {print " - " $1 " (" $7 ")"}' /etc/passwd
  c_reset
}

audit_empty_passwords() {
  c_yellow
  echo "Users with EMPTY passwords:"
  awk -F: '($2==""){print " - " $1}' /etc/shadow
  c_reset
}

audit_admin_users() {
  c_yellow
  echo "Users with sudo/admin access:"
  getent group sudo adm wheel 2>/dev/null | awk -F: '{print " - " $1 ": " $4}'
  c_reset
}

lock_user_prompt() {
  read -rp "Enter username to LOCK (or blank to skip): " u
  if [ -n "$u" ] && id "$u" &>/dev/null; then
    if confirm "Lock user $u?"; then
      passwd -l "$u"
      echo "User $u locked."
    fi
  fi
}

remove_sudo_prompt() {
  read -rp "Enter username to REMOVE from sudo (or blank to skip): " u
  if [ -n "$u" ] && id "$u" &>/dev/null; then
    if confirm "Remove $u from sudo group?"; then
      deluser "$u" sudo 2>/dev/null || gpasswd -d "$u" sudo
      echo "Removed $u from sudo."
    fi
  fi
}

main() {
  show_header
  backup_critical_files
  pause

  audit_uid0_users
  pause

  audit_login_users
  pause

  audit_empty_passwords
  pause

  audit_admin_users
  pause

  lock_user_prompt
  remove_sudo_prompt

  c_green
  echo "User audit complete. No system services were modified."
  c_reset
}

require_root
main
