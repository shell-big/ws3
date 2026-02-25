#!/bin/bash
# =============================================================================
# ws3 Navigator Control System - セットアップスクリプト
# =============================================================================
# 対象環境: Raspberry Pi OS (標準構成) + BlueRobotics Navigator ボード
#
# このスクリプトは以下を自動的にセットアップします:
#   1. 必要なシステムパッケージのインストール
#   2. Rust / Cargo のインストール
#   3. I2C/SPI/GPIO ハードウェアインターフェースの有効化（PWM制御に必須）
#   4. BlueRobotics navigator-lib のクローン＆ビルド
#   5. GStreamer 関連パッケージのインストール
#   6. アプリケーション本体のビルド
#   7. systemd サービスの登録・有効化
#
# 実行方法:
#   chmod +x setup.sh
#   sudo bash setup.sh
# =============================================================================

set -euo pipefail

# --- カラー出力用定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

banner() {
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo ""
}

# =============================================================================
# 設定値（環境に合わせて変更してください）
# =============================================================================

# インストール先ユーザー（デフォルト: 現在のユーザー）
INSTALL_USER="${SUDO_USER:-pi}"
USER_HOME="/home/${INSTALL_USER}"
# プロジェクトディレクトリ（このスクリプトがある場所）
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# navigator-lib のクローン先
NAVIGATOR_LIB_DIR="${USER_HOME}/navigator-lib"
# ビルド済みバイナリへのパス
BINARY_PATH="$PROJECT_DIR/bin/navigator_control"
# systemd サービス名
SERVICE_NAME="navigator_control"

# =============================================================================
# ユーザー権限コマンド実行ヘルパー
# sudo -u pi は HOME=/root を引き継ぐため cargo/rustc が見つからない問題を回避する
# run_as_user <command...> の形で使う
# =============================================================================
run_as_user() {
  sudo -H -u "$INSTALL_USER" \
    env HOME="${USER_HOME}" \
        RUSTUP_HOME="${USER_HOME}/.rustup" \
        CARGO_HOME="${USER_HOME}/.cargo" \
        PATH="${USER_HOME}/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$@"
}

# =============================================================================
# 前提チェック
# =============================================================================
banner "前提条件の確認"

if [ "$EUID" -ne 0 ]; then
  log_error "このスクリプトは sudo で実行してください。"
  echo "  例: sudo bash setup.sh"
  exit 1
fi
log_ok "root 権限を確認"

# OS 確認（Raspberry Pi / Debian 系）
if ! command -v apt-get &>/dev/null; then
  log_error "apt-get が見つかりません。Debian/Ubuntu 系の OS で実行してください。"
  exit 1
fi
log_ok "apt-get を確認"

# =============================================================================
# ステップ 1: システムパッケージのインストール
# =============================================================================
banner "ステップ 1/7: システムパッケージのインストール"

log_info "パッケージリストを更新中..."
apt-get update -qq

PACKAGES=(
  cmake
  git
  build-essential
  pkg-config
  curl
  # I2C / SPI 開発用ヘッダー（navigator-lib の build.rs が C++ コアをビルドする際に必要）
  libi2c-dev
  libgpiod-dev
  i2c-tools
  python3-smbus
)

log_info "必要パッケージをインストール中: ${PACKAGES[*]}"
apt-get install -y "${PACKAGES[@]}"
log_ok "システムパッケージのインストール完了"

# =============================================================================
# ステップ 2: Rust / Cargo のインストール
# =============================================================================
banner "ステップ 2/7: Rust / Cargo のインストール"

RUSTUP_BIN="${USER_HOME}/.cargo/bin/rustup"

if [ ! -f "$RUSTUP_BIN" ]; then
  log_info "rustup をインストール中..."
  # sudo -H で HOME を正しく設定してからインストール
  sudo -H -u "$INSTALL_USER" \
    env HOME="${USER_HOME}" \
    bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
  log_ok "rustup のインストール完了"
else
  log_ok "rustup は既にインストール済みです"
fi

# =============================================================================
# 重要: navigator-lib の cpy-binder が -Zunpretty=expanded (nightly 専用フラグ) を
# 使用するため、nightly ツールチェーンが必須。
# =============================================================================

# nightly ツールチェーンをインストール・最新化
log_info "Rust nightly ツールチェーンをインストール・更新中..."
run_as_user "$RUSTUP_BIN" toolchain install nightly
run_as_user "$RUSTUP_BIN" default nightly
log_ok "Rust nightly ツールチェーンの設定完了"

# ツールチェーン名と実際の cargo バイナリパスを解決
TOOLCHAIN_NAME=$(run_as_user "$RUSTUP_BIN" toolchain list | grep "nightly.*default" | awk '{print $1}')
if [ -z "$TOOLCHAIN_NAME" ]; then
  TOOLCHAIN_NAME=$(run_as_user "$RUSTUP_BIN" toolchain list | grep nightly | head -1 | awk '{print $1}')
fi
TOOLCHAIN_BIN="${USER_HOME}/.rustup/toolchains/${TOOLCHAIN_NAME}/bin"
ACTUAL_CARGO="${TOOLCHAIN_BIN}/cargo"
if [ ! -f "$ACTUAL_CARGO" ]; then
  log_warn "toolchain 直接パスが見つからないためシムを使用します"
  ACTUAL_CARGO="${USER_HOME}/.cargo/bin/cargo"
  TOOLCHAIN_BIN="${USER_HOME}/.cargo/bin"
fi
log_info "使用する cargo: $ACTUAL_CARGO"
# ツールチェーンの bin を PATH に加えて rustc も確実に見えるようにする
run_as_user env PATH="${TOOLCHAIN_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "$ACTUAL_CARGO" --version

# =============================================================================
# ステップ 3/7: I2C / SPI / GPIO ハードウェアインターフェースの有効化
# navigator-lib は I2C 経由で PCA9685 (PWMコントローラ) を制御します。
# 素の Raspberry Pi OS ではデフォルトで無効なので必ず有効化してください。
# =============================================================================
banner "ステップ 3/7: I2C / SPI / GPIO ハードウェア設定"

# --- /boot/firmware/config.txt (新しい Pi) または /boot/config.txt の確認 ---
BOOT_CONFIG=""
if [ -f "/boot/firmware/config.txt" ]; then
  BOOT_CONFIG="/boot/firmware/config.txt"   # Raspberry Pi OS Bookworm 以降
elif [ -f "/boot/config.txt" ]; then
  BOOT_CONFIG="/boot/config.txt"             # 従来の Raspberry Pi OS
fi

if [ -n "$BOOT_CONFIG" ]; then
  log_info "ブート設定ファイル: $BOOT_CONFIG"

  # I2C の有効化
  if grep -q "^dtparam=i2c_arm=on" "$BOOT_CONFIG"; then
    log_ok "I2C はすでに有効です (dtparam=i2c_arm=on)"
  else
    log_info "I2C を有効化中..."
    echo "dtparam=i2c_arm=on" >> "$BOOT_CONFIG"
    log_ok "I2C を有効化しました (再起動後に反映)"
    REBOOT_REQUIRED=true
  fi

  # SPI の有効化（navigator-lib が SPI も利用する場合があるため）
  if grep -q "^dtparam=spi=on" "$BOOT_CONFIG"; then
    log_ok "SPI はすでに有効です (dtparam=spi=on)"
  else
    log_info "SPI を有効化中..."
    echo "dtparam=spi=on" >> "$BOOT_CONFIG"
    log_ok "SPI を有効化しました (再起動後に反映)"
    REBOOT_REQUIRED=true
  fi

  # SPI1 オーバーレイの有効化
  # Navigator ボードの ICM20689 (IMU) は SPI1 (/dev/spidev1.0) を使用する。
  # dtparam=spi=on だけでは SPI0 しか有効にならないため、spi1 オーバーレイが別途必要。
  if grep -q "^dtoverlay=spi1" "$BOOT_CONFIG"; then
    log_ok "SPI1 はすでに有効です (dtoverlay=spi1-3cs)"
  else
    log_info "SPI1 オーバーレイを有効化中 (Navigator IMU 用)..."
    echo "dtoverlay=spi1-3cs" >> "$BOOT_CONFIG"
    log_ok "SPI1 を有効化しました (再起動後に反映)"
    REBOOT_REQUIRED=true
  fi
else
  log_warn "/boot/config.txt が見つかりません。"
  log_warn "手動で I2C / SPI を有効化してください: sudo raspi-config"
fi

# --- カーネルモジュールの即時ロード（再起動なしで今すぐ試す場合）---
if ! lsmod | grep -q "^i2c_dev"; then
  log_info "i2c-dev カーネルモジュールをロード中..."
  modprobe i2c-dev || log_warn "i2c-dev のロードに失敗しました（再起動後に自動でロードされます）"
fi
if ! lsmod | grep -q "^spi_bcm2835"; then
  log_info "spi-bcm2835 カーネルモジュールをロード中..."
  modprobe spi-bcm2835 || true
fi

# 起動時にモジュールが自動ロードされるよう /etc/modules に追記
for module in i2c-dev i2c-bcm2708; do
  if ! grep -qxF "$module" /etc/modules 2>/dev/null; then
    echo "$module" >> /etc/modules
    log_info "  /etc/modules に '$module' を追加しました"
  fi
done
log_ok "カーネルモジュールの設定完了"

# --- ユーザーをハードウェアアクセスグループに追加 ---
log_info "'${INSTALL_USER}' を I2C / SPI / GPIO グループに追加中..."
for grp in i2c spi gpio; do
  if getent group "$grp" &>/dev/null; then
    usermod -aG "$grp" "$INSTALL_USER"
    log_ok "  グループ '$grp' に追加しました"
  else
    log_warn "  グループ '$grp' が存在しません（スキップ）"
  fi
done

# I2C デバイス確認（i2cdetect）
if command -v i2cdetect &>/dev/null; then
  log_info "I2C デバイスをスキャン中（bus 1）..."
  i2cdetect -y 1 2>/dev/null || log_warn "i2cdetect が失敗しました（I2C が未有効の可能性）"
fi

# =============================================================================
# ステップ 3: navigator-lib のクローン＆ビルド
# =============================================================================
banner "ステップ 4/7: navigator-lib のクローン＆ビルド"

if [ -d "$NAVIGATOR_LIB_DIR" ]; then
  log_warn "navigator-lib はすでに存在します: $NAVIGATOR_LIB_DIR"
  log_info "最新版に更新します（git pull）..."
  sudo -u "$INSTALL_USER" git -C "$NAVIGATOR_LIB_DIR" pull
else
  log_info "navigator-lib をクローン中..."
  sudo -u "$INSTALL_USER" git clone \
    https://github.com/bluerobotics/navigator-lib.git \
    "$NAVIGATOR_LIB_DIR"
  log_ok "クローン完了: $NAVIGATOR_LIB_DIR"
fi

log_info "navigator-lib をビルド中（Debug モード）..."

# 旧バージョンの cargo で汚染されたレジストリキャッシュを削除する
CARGO_REGISTRY="${USER_HOME}/.cargo/registry"
if [ -d "$CARGO_REGISTRY" ]; then
  log_info "cargo レジストリキャッシュをクリア中: $CARGO_REGISTRY"
  rm -rf "$CARGO_REGISTRY"
  log_ok "キャッシュをクリアしました"
fi

# ツールチェーン bin を PATH に加えて rustc も確実に解決できるようにする
run_as_user \
  env PATH="${TOOLCHAIN_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  bash -c "cd '${NAVIGATOR_LIB_DIR}' && '${ACTUAL_CARGO}' build"
log_ok "navigator-lib のビルド完了"
log_info "  ライブラリパス: $NAVIGATOR_LIB_DIR/target/debug"

# =============================================================================
# ステップ 4: GStreamer 関連パッケージのインストール
# =============================================================================
banner "ステップ 5/7: GStreamer のインストール"

GSTREAMER_PACKAGES=(
  # GStreamer コア
  gstreamer1.0-tools
  gstreamer1.0-plugins-base
  gstreamer1.0-plugins-good
  gstreamer1.0-plugins-bad
  gstreamer1.0-plugins-ugly
  # 開発用ライブラリ（ビルドに必要）
  libgstreamer1.0-dev
  libgstreamer-plugins-base1.0-dev
  # H.264 エンコード (x264)
  gstreamer1.0-x
  # ネットワーク経由のストリーミング（RTP/UDP）
  gstreamer1.0-rtsp
  # カメラデバイス (V4L2)
  gstreamer1.0-plugins-good   # v4l2src は good に含まれる
)

log_info "GStreamer パッケージをインストール中..."
apt-get install -y "${GSTREAMER_PACKAGES[@]}"
log_ok "GStreamer のインストール完了"

# インストール確認
if command -v gst-launch-1.0 &>/dev/null; then
  log_ok "gst-launch-1.0 確認: $(gst-launch-1.0 --version | head -1)"
else
  log_warn "gst-launch-1.0 が見つかりません。パスを確認してください。"
fi

# =============================================================================
# ステップ 5: アプリケーション本体のビルド
# =============================================================================
banner "ステップ 6/7: navigator_control アプリケーションのビルド"

log_info "プロジェクトディレクトリ: $PROJECT_DIR"
cd "$PROJECT_DIR"

# 以前のビルド成果物をクリーン
log_info "以前のビルド成果物をクリーン中..."
if [ -d "obj" ] || [ -d "bin" ]; then
  run_as_user make -f Makefile.mk clean || true
fi

log_info "ビルド中... (make -f Makefile.mk)"
run_as_user bash -c "cd '${PROJECT_DIR}' && make -f Makefile.mk"

if [ -f "$BINARY_PATH" ]; then
  log_ok "ビルド成功: $BINARY_PATH"
else
  log_error "ビルドに失敗しました。上記のエラーを確認してください。"
  exit 1
fi

# バイナリの実行権限を確認
chmod +x "$BINARY_PATH"

# =============================================================================
# ステップ 6: systemd サービスの登録・有効化
# =============================================================================
banner "ステップ 7/7: systemd サービスの設定"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
log_info "サービスファイルを生成中: $SERVICE_FILE"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Navigator Control Service
After=network.target

[Service]
ExecStart=${BINARY_PATH}
WorkingDirectory=${PROJECT_DIR}
Environment="LD_LIBRARY_PATH=${USER_HOME}/navigator-lib/target/debug"
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=3
User=${INSTALL_USER}
SupplementaryGroups=i2c spi gpio

[Install]
WantedBy=multi-user.target
EOF

log_ok "サービスファイルを作成しました"
log_info "  ExecStart       : $BINARY_PATH"
log_info "  WorkingDirectory: $PROJECT_DIR"
log_info "  User            : $INSTALL_USER"

log_info "systemd デーモンを再読み込み中..."
systemctl daemon-reload

log_info "サービスを自動起動に登録中..."
systemctl enable "${SERVICE_NAME}.service"

log_info "サービスを起動中..."
systemctl start "${SERVICE_NAME}.service"

# 起動確認
sleep 2
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  log_ok "サービスが正常に起動しました！"
else
  log_warn "サービスがアクティブではありません。以下で状態を確認してください:"
  echo "  sudo systemctl status ${SERVICE_NAME}.service"
fi

# =============================================================================
# 完了メッセージ
# =============================================================================
banner "セットアップ完了"

echo -e "${GREEN}すべてのセットアップが完了しました！${NC}"
echo ""
echo "--- 便利なコマンド ---"
echo ""
echo "  サービスの状態確認:"
echo "    sudo systemctl status ${SERVICE_NAME}.service"
echo ""
echo "  リアルタイムログの表示:"
echo "    journalctl -u ${SERVICE_NAME}.service -f"
echo ""
echo "  サービスの手動停止:"
echo "    sudo systemctl stop ${SERVICE_NAME}.service"
echo ""
echo "  サービスの手動再起動:"
echo "    sudo systemctl restart ${SERVICE_NAME}.service"
echo ""
echo "  自動起動の無効化:"
echo "    sudo systemctl disable ${SERVICE_NAME}.service"
echo ""
echo "  GStreamer パイプラインのテスト（カメラ1）:"
echo "    gst-launch-1.0 v4l2src device=/dev/video2 ! fakesink"
echo ""
echo "  I2C デバイス確認（PCA9685 は 0x40 に現れます）:"
echo "    sudo i2cdetect -y 1"
echo ""

# 再起動が必要な場合は警告
if [ "${REBOOT_REQUIRED:-false}" = "true" ]; then
  echo ""
  echo -e "${YELLOW}⚠️  注意: I2C/SPI を有効化したため、設定を反映するには再起動が必要です。${NC}"
  echo "    sudo reboot"
  echo ""
fi
