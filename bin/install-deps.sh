#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

LIBRESPEED_VERSION="1.0.12"
INSTALL_LIBRESPEED="${INSTALL_LIBRESPEED:-yes}"
FORCE_LIBRESPEED_INSTALL="${FORCE_LIBRESPEED_INSTALL:-no}"
TMPDIR_SPEEDMON=""

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root: sudo $0"
    exit 1
  fi
}

cleanup() {
  if [[ -n "${TMPDIR_SPEEDMON:-}" && -d "${TMPDIR_SPEEDMON}" ]]; then
    rm -rf "${TMPDIR_SPEEDMON}"
  fi
}

detect_arch() {
  local arch
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64)
      echo "linux_amd64"
      ;;
    aarch64|arm64)
      echo "linux_arm64"
      ;;
    armv7l|armv7|armhf)
      echo "linux_armv7"
      ;;
    *)
      echo "ERROR: Unsupported architecture: ${arch}" >&2
      exit 1
      ;;
  esac
}

install_base_packages() {
  apt update
  apt install -y \
    bash \
    curl \
    dnsutils \
    iproute2 \
    iputils-ping \
    traceroute \
    coreutils \
    util-linux \
    procps \
    ca-certificates \
    cron \
    jq \
    tar \
    file \
    python3 \
    python3-pip \
    python3-pil \
    python3-gpiozero \
    i2c-tools
}

install_python_display_deps() {
  echo "Checking Python display dependencies ..."

  if python3 - <<'PY'
import importlib
mods = ["gpiozero", "PIL", "luma.oled", "luma.core"]
for m in mods:
    importlib.import_module(m)
print("ok")
PY
  then
    echo "Python display dependencies already available."
    return 0
  fi

  echo "Installing/repairing Python display dependencies ..."
  apt install -y python3-dev python3-setuptools python3-wheel || true
  python3 -m pip install --break-system-packages --upgrade pip || true
  python3 -m pip install --break-system-packages luma.oled
}

validate_librespeed_binary() {
  local bin_path="$1"

  [[ -f "$bin_path" ]] || {
    echo "ERROR: Binary not found: $bin_path" >&2
    return 1
  }

  chmod 755 "$bin_path"

  if ! file "$bin_path" | grep -qi 'ELF'; then
    echo "ERROR: Downloaded file is not an ELF binary: $bin_path" >&2
    file "$bin_path" >&2 || true
    return 1
  fi

  local help_out=""
  help_out="$("$bin_path" --help 2>&1 || true)"

  if [[ -z "$help_out" ]]; then
    echo "ERROR: librespeed-cli smoke test failed: --help produced no output" >&2
    return 1
  fi

  if ! grep -q "LibreSpeed" <<<"$help_out"; then
    echo "ERROR: librespeed-cli smoke test failed: --help output looks wrong" >&2
    printf '%s\n' "$help_out" | head -20 >&2
    return 1
  fi

  return 0
}

install_librespeed_cli() {
  [[ "${INSTALL_LIBRESPEED}" == "yes" ]] || return 0

  local target="/usr/local/bin/librespeed-cli"
  local backup=""
  local asset_arch
  local url
  local candidate

  if [[ -x "$target" && "${FORCE_LIBRESPEED_INSTALL}" != "yes" ]]; then
    echo "librespeed-cli already present at $target"
    echo "Skipping replacement. Set FORCE_LIBRESPEED_INSTALL=yes to reinstall."
    return 0
  fi

  asset_arch="$(detect_arch)"
  url="https://github.com/librespeed/speedtest-cli/releases/download/v${LIBRESPEED_VERSION}/librespeed-cli_${LIBRESPEED_VERSION}_${asset_arch}.tar.gz"

  TMPDIR_SPEEDMON="$(mktemp -d)"
  trap cleanup EXIT

  echo "Downloading librespeed-cli ${LIBRESPEED_VERSION} for ${asset_arch} ..."
  curl -fL --retry 3 --connect-timeout 20 -o "${TMPDIR_SPEEDMON}/librespeed-cli.tar.gz" "${url}"

  echo "Inspecting archive ..."
  tar -tzf "${TMPDIR_SPEEDMON}/librespeed-cli.tar.gz" >/dev/null

  tar -xzf "${TMPDIR_SPEEDMON}/librespeed-cli.tar.gz" -C "${TMPDIR_SPEEDMON}"

  candidate="${TMPDIR_SPEEDMON}/librespeed-cli"
  if [[ ! -f "$candidate" ]]; then
    echo "ERROR: librespeed-cli binary not found in extracted archive." >&2
    find "${TMPDIR_SPEEDMON}" -maxdepth 2 -type f >&2 || true
    exit 1
  fi

  echo "Validating downloaded binary ..."
  validate_librespeed_binary "$candidate"

  if [[ -f "$target" ]]; then
    backup="${target}.bak.$(date +%s)"
    cp -a "$target" "$backup"
    echo "Existing binary backed up to: $backup"
  fi

  install -m 0755 "$candidate" "$target"

  echo "Installed librespeed-cli to $target"
  echo "Smoke test after install ..."
  "$target" --help | head -5

  echo "librespeed-cli installation successful."
}

print_i2c_hint() {
  echo
  echo "Note:"
  echo "  Make sure I2C is enabled on the Raspberry Pi."
  echo "  You can enable it with:"
  echo "    raspi-config"
  echo "  Then: Interface Options -> I2C -> Enable"
}

main() {
  require_root
  install_base_packages
  install_python_display_deps
  install_librespeed_cli
  print_i2c_hint
  echo "Dependencies installed."
}

main "$@"
