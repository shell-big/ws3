#!/bin/bash
# =============================================================================
# ws3 Navigator Control System - アンインストールスクリプト
# =============================================================================
# setup.sh が行った変更を できるだけ安全に元に戻します。
# 目標:
#   ・環境を壊さない（システムパッケージ・GStreamer は削除しない）
#   ・再セットアップできる状態に戻す（setup.sh を再実行すれば復元可能）
#
# 実行方法:
#   chmod +x delete.sh
#   sudo bash delete.sh
# =============================================================================

set -euo pipefail

# --- カラー出力用定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_skip()  { echo -e "${YELLOW}[SKIP]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

banner() {
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo ""
}

confirm() {
  local msg="$1"
  echo -e "${YELLOW}[CONFIRM]${NC} $msg"
  read -r -p "         実行しますか？ [y/N]: " ans
  [[ "${ans,,}" == "y" ]]
}

# =============================================================================
# 設定値（setup.sh と同じ値を使う）
# =============================================================================
INSTALL_USER="${SUDO_USER:-pi}"
USER_HOME="/home/${INSTALL_USER}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAVIGATOR_LIB_DIR="${USER_HOME}/navigator-lib"
SERVICE_NAME="navigator_control"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# =============================================================================
# 前提チェック
# =============================================================================
banner "前提条件の確認"

if [ "$EUID" -ne 0 ]; then
  log_error "このスクリプトは sudo で実行してください。"
  echo "  例: sudo bash delete.sh"
  exit 1
fi
log_ok "root 権限を確認"
log_info "対象ユーザー: $INSTALL_USER"
log_info "プロジェクト: $PROJECT_DIR"

echo ""
echo -e "${YELLOW}⚠️  このスクリプトは setup.sh の変更を元に戻します。${NC}"
echo "   以下は削除・変更されます:"
echo "     - systemd サービス (${SERVICE_NAME})"
echo "     - ビルド成果物 (bin/, obj/)"
echo "     - navigator-lib クローン (${NAVIGATOR_LIB_DIR})"
echo "     - Rust / rustup (任意)"
echo "     - I2C/SPI カーネルモジュール設定 (任意)"
echo "   以下は変更しません:"
echo "     - システムパッケージ (cmake, git, build-essential 等)"
echo "     - GStreamer パッケージ"
echo "     - ソースコード (src/, include/, config.ini 等)"
echo ""
read -r -p "続行しますか？（Ctrl+C でキャンセル）[y/N]: " ans
if [[ "${ans,,}" != "y" ]]; then
  echo "キャンセルしました。"
  exit 0
fi

# =============================================================================
# ステップ 1: systemd サービスの停止・削除
# =============================================================================
banner "ステップ 1/5: systemd サービスの停止・削除"

if systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
  log_info "サービスを停止中..."
  systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true

  log_info "自動起動を無効化中..."
  systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true

  if [ -f "$SERVICE_FILE" ]; then
    log_info "サービスファイルを削除中: $SERVICE_FILE"
    rm -f "$SERVICE_FILE"
    log_ok "サービスファイルを削除しました"
  fi

  log_info "systemd デーモンを再読み込み中..."
  systemctl daemon-reload
  log_ok "systemd サービスの削除完了"
else
  log_skip "サービス ${SERVICE_NAME} は登録されていません"
fi

# =============================================================================
# ステップ 2: ビルド成果物の削除
# =============================================================================
banner "ステップ 2/5: ビルド成果物の削除"

for dir in "bin" "obj"; do
  if [ -d "${PROJECT_DIR}/${dir}" ]; then
    log_info "${dir}/ を削除中..."
    rm -rf "${PROJECT_DIR:?}/${dir}"
    log_ok "${dir}/ を削除しました"
  else
    log_skip "${dir}/ は存在しません"
  fi
done

# =============================================================================
# ステップ 3: navigator-lib の削除
# =============================================================================
banner "ステップ 3/5: navigator-lib の削除"

if [ -d "$NAVIGATOR_LIB_DIR" ]; then
  log_info "navigator-lib を削除中: $NAVIGATOR_LIB_DIR"
  rm -rf "$NAVIGATOR_LIB_DIR"
  log_ok "navigator-lib を削除しました"
else
  log_skip "navigator-lib は存在しません: $NAVIGATOR_LIB_DIR"
fi

# =============================================================================
# ステップ 4: Rust / rustup の削除（任意）
# =============================================================================
banner "ステップ 4/5: Rust / rustup の削除（任意）"

RUSTUP_BIN="${USER_HOME}/.cargo/bin/rustup"

if [ -f "$RUSTUP_BIN" ]; then
  log_info "rustup が見つかりました: $RUSTUP_BIN"
  if confirm "Rust と rustup を完全に削除しますか？（他の用途に使っていない場合のみ推奨）"; then
    log_info "rustup self uninstall を実行中..."
    sudo -H -u "$INSTALL_USER" \
      env HOME="${USER_HOME}" \
          RUSTUP_HOME="${USER_HOME}/.rustup" \
          CARGO_HOME="${USER_HOME}/.cargo" \
      "$RUSTUP_BIN" self uninstall -y
    log_ok "Rust / rustup を削除しました"
  else
    log_skip "Rust / rustup は保持します"
  fi
else
  log_skip "rustup が見つかりません（インストール済みではない）"
fi

# =============================================================================
# ステップ 5: I2C / SPI 設定の削除（任意）
# =============================================================================
banner "ステップ 5/5: I2C / SPI / カーネルモジュール設定の削除（任意）"

# --- ブート設定ファイルの検出 ---
BOOT_CONFIG=""
if [ -f "/boot/firmware/config.txt" ]; then
  BOOT_CONFIG="/boot/firmware/config.txt"
elif [ -f "/boot/config.txt" ]; then
  BOOT_CONFIG="/boot/config.txt"
fi

if [ -n "$BOOT_CONFIG" ]; then
  NEEDS_BOOT_CHANGE=false
  grep -q "^dtparam=i2c_arm=on" "$BOOT_CONFIG" && NEEDS_BOOT_CHANGE=true
  grep -q "^dtparam=spi=on"     "$BOOT_CONFIG" && NEEDS_BOOT_CHANGE=true

  if $NEEDS_BOOT_CHANGE; then
    log_info "ブート設定: $BOOT_CONFIG"
    log_warn "I2C/SPI 設定が見つかりました。他のハードウェアでも I2C/SPI を使っている場合は削除しないでください。"
    if confirm "I2C (dtparam=i2c_arm=on) と SPI (dtparam=spi=on) を無効化しますか？（再起動後に反映）"; then
      # バックアップを作成してから変更
      cp "$BOOT_CONFIG" "${BOOT_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
      log_ok "バックアップ作成: ${BOOT_CONFIG}.bak.*"

      sed -i '/^dtparam=i2c_arm=on/d' "$BOOT_CONFIG"
      sed -i '/^dtparam=spi=on/d'     "$BOOT_CONFIG"
      log_ok "I2C / SPI の設定を削除しました（再起動後に反映）"
      REBOOT_REQUIRED=true
    else
      log_skip "ブート設定はそのまま保持します"
    fi
  else
    log_skip "ブート設定に I2C/SPI の記述はありません"
  fi
fi

# --- /etc/modules からモジュールを削除 ---
if grep -qE "^(i2c-dev|i2c-bcm2708)$" /etc/modules 2>/dev/null; then
  if confirm "/etc/modules から i2c-dev・i2c-bcm2708 を削除しますか？"; then
    sed -i '/^i2c-dev$/d'     /etc/modules
    sed -i '/^i2c-bcm2708$/d' /etc/modules
    log_ok "/etc/modules からモジュール設定を削除しました"
  else
    log_skip "/etc/modules はそのまま保持します"
  fi
else
  log_skip "/etc/modules に i2c モジュールの記述はありません"
fi

# --- ユーザーのグループ削除（gpasswd）---
log_info "'${INSTALL_USER}' を I2C / SPI / GPIO グループから除外するか確認..."
for grp in i2c spi gpio; do
  if getent group "$grp" &>/dev/null && id -nG "$INSTALL_USER" | grep -qw "$grp"; then
    if confirm "ユーザー '${INSTALL_USER}' をグループ '${grp}' から除外しますか？"; then
      gpasswd -d "$INSTALL_USER" "$grp" && log_ok "  グループ '$grp' から除外しました"
    else
      log_skip "  グループ '$grp' はそのまま保持します"
    fi
  else
    log_skip "  ユーザーはグループ '$grp' に属していません"
  fi
done

# =============================================================================
# 完了メッセージ
# =============================================================================
banner "アンインストール完了"

echo -e "${GREEN}setup.sh の変更の削除が完了しました。${NC}"
echo ""
echo "--- 削除された項目 ---"
echo "  ✓ systemd サービス (${SERVICE_NAME})"
echo "  ✓ ビルド成果物 (bin/, obj/)"
echo "  ✓ navigator-lib (${NAVIGATOR_LIB_DIR})"
echo ""
echo "--- 保持された項目 ---"
echo "  • システムパッケージ (cmake, git, build-essential 等)"
echo "  • GStreamer パッケージ"
echo "  • ソースコード (src/, include/, config.ini 等)"
echo ""
echo "--- 再セットアップするには ---"
echo "    sudo bash setup.sh"
echo ""

if [ "${REBOOT_REQUIRED:-false}" = "true" ]; then
  echo ""
  echo -e "${YELLOW}⚠️  I2C/SPI の変更を反映するため再起動が必要です。${NC}"
  echo "    sudo reboot"
  echo ""
fi
