#!/bin/sh
# LANYU Universal Windows Server 2022 Reinstall
# Target: Windows Server 2022 Datacenter, Simplified Chinese, Desktop Experience
# Source selection: bin456789/reinstall auto-selects an official ISO via ntriver
# WARNING: the VPS system disk will be erased after reboot.

set -eu

RDP_PORT="${RDP_PORT:-3389}"
REINSTALL="/root/reinstall.sh"

say() {
  printf '%s\n' "$*"
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    say "ERROR: Please run as root. Try: sudo -i"
    exit 1
  fi
}

check_arch() {
  ARCH="$(uname -m 2>/dev/null || true)"
  case "$ARCH" in
    x86_64|amd64) ;;
    *)
      say "ERROR: This profile requires x86_64/amd64. Detected: ${ARCH:-unknown}"
      exit 1
      ;;
  esac
}

check_container() {
  if [ -d /proc/vz ] && [ ! -d /proc/bc ]; then
    say "ERROR: OpenVZ is not supported by the upstream reinstall project."
    exit 1
  fi

  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT="$(systemd-detect-virt 2>/dev/null || true)"
    case "$VIRT" in
      lxc|openvz|docker|podman|container-other)
        say "ERROR: Container virtualization detected: $VIRT"
        say "Use a full VM/KVM VPS."
        exit 1
        ;;
    esac
  fi
}

install_base_tools() {
  say "[1/5] Installing/checking base tools..."

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y bash curl wget ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y bash curl wget ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    yum install -y bash curl wget ca-certificates
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache bash curl wget ca-certificates
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install bash curl wget ca-certificates
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm bash curl wget ca-certificates
  else
    say "ERROR: Unsupported package manager."
    say "Supported: apt, dnf, yum, apk, zypper, pacman"
    exit 1
  fi

  command -v bash >/dev/null 2>&1 || { say "ERROR: bash is missing."; exit 1; }
  command -v curl >/dev/null 2>&1 || { say "ERROR: curl is missing."; exit 1; }
}

check_resources() {
  say "[2/5] Checking RAM and disk..."

  MEM_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
  if [ "${MEM_KB:-0}" -lt 950000 ]; then
    say "ERROR: Less than about 1 GiB RAM detected."
    exit 1
  fi

  if command -v lsblk >/dev/null 2>&1; then
    DISK_BYTES="$(lsblk -bdn -o SIZE,TYPE 2>/dev/null | awk '$2=="disk" && $1>m {m=$1} END {print m+0}')"
    if [ "${DISK_BYTES:-0}" -gt 0 ] && [ "$DISK_BYTES" -lt 26843545600 ]; then
      say "ERROR: Largest disk is smaller than 25 GiB."
      exit 1
    fi
  fi
}

download_upstream() {
  say "[3/5] Downloading latest reinstall.sh..."

  TMP="${REINSTALL}.tmp"
  rm -f "$TMP"

  if ! curl -fsSL --connect-timeout 15 --retry 3 \
      "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh" \
      -o "$TMP"; then
    say "GitHub raw failed; trying CNB mirror..."
    curl -fsSL --connect-timeout 15 --retry 3 \
      "https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh" \
      -o "$TMP"
  fi

  bash -n "$TMP"
  mv "$TMP" "$REINSTALL"
  chmod +x "$REINSTALL"
}

check_iso_index() {
  say "[4/5] Checking automatic Windows ISO source..."

  if ! curl -fsSL --connect-timeout 15 --max-time 45 \
      "https://ntriver.org/download-windows-office" \
      -o /tmp/lanyu-ntriver-test.html; then
    say "ERROR: Cannot reach ntriver.org from this VPS."
    say "Do not reboot. Try another VPS/network or retry later."
    rm -f /tmp/lanyu-ntriver-test.html
    exit 1
  fi

  rm -f /tmp/lanyu-ntriver-test.html
}

run_reinstall() {
  say "[5/5] Preparing Windows Server 2022 reinstall..."
  say
  say "Target: Windows Server 2022 Datacenter"
  say "Language: Simplified Chinese (zh-cn)"
  say "Desktop: yes (ServerDatacenter, not ServerDatacenterCore)"
  say "RDP port: $RDP_PORT"
  say
  say "WARNING: After reboot, the whole system disk will be erased."
  printf 'Type DD to continue: '
  IFS= read -r CONFIRM
  if [ "$CONFIRM" != "DD" ]; then
    say "Cancelled."
    exit 0
  fi

  set -- windows \
    --image-name "Windows Server 2022 ServerDatacenter" \
    --lang zh-cn \
    --username Administrator \
    --rdp-port "$RDP_PORT" \
    --allow-ping

  DMI=""
  [ -r /sys/class/dmi/id/sys_vendor ] && DMI="$DMI $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  [ -r /sys/class/dmi/id/product_name ] && DMI="$DMI $(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
  case "$DMI" in
    *Google*|*google*)
      say "Google Cloud detected: enabling BIOS boot workaround."
      set -- "$@" --force-boot-mode bios
      ;;
  esac

  bash "$REINSTALL" "$@"

  say
  say "============================================================"
  say "Preparation finished."
  say "If there were NO errors above, run:"
  say
  say "  reboot"
  say
  say "Then wait for Windows installation to complete."
  say "RDP user: Administrator"
  say "RDP port: $RDP_PORT"
  say "============================================================"
}

need_root
check_arch
check_container
install_base_tools
check_resources
download_upstream
check_iso_index
run_reinstall
