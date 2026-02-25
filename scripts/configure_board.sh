#!/usr/bin/env bash
# =============================================================================
# BlueRobotics configure_board.sh (同梱版)
# 元リポジトリ: https://github.com/bluerobotics/blueos-docker
# パス        : install/boards/configure_board.sh
#
# [重要] このファイルは外部からの curl | bash を避けるためリポジトリに同梱しています。
#        外部スクリプトをアップストリームに追従させる場合は、上記 URL から取得し
#        内容を確認した上でこのファイルを更新してください。
# =============================================================================

# Detect and configure hardware for each supported plataform
VERSION="${VERSION:-master}"
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-bluerobotics/BlueOS}
REMOTE="${REMOTE:-https://raw.githubusercontent.com/${GITHUB_REPOSITORY}}"
ROOT="$REMOTE/$VERSION"
CONFIGURE_BOARD_PATH="$ROOT/install/boards"

# SCRIPT_DIR: このスクリプト自身があるディレクトリ（同梱スクリプトを参照するため）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function board_not_detected {
    echo "Hardware not identified in $1, please report back the following line:"
    echo "---"
    echo "$(echo $2 | gzip | base64 -w0)" # Decode with `echo $CONTENT | base64 -d | gunzip`
    echo "---"
}

echo "Detecting board type"
# device-tree/model is not standard but is the only way to detect raspberry pi hardware reliable
if [ -f "/proc/device-tree/model" ]; then
    CPU_MODEL=$(tr -d '\0' < /proc/device-tree/model)
    if [[ $CPU_MODEL =~ Raspberry\ Pi\ [0-3] ]]; then
        echo "Detected BCM28XX via device tree"
        # 同梱スクリプトを優先使用。存在しない場合はリモートから取得
        if [ -f "$SCRIPT_DIR/bcm_28xx.sh" ]; then
            bash "$SCRIPT_DIR/bcm_28xx.sh"
        else
            curl --retry 6 --max-time 15 --retry-all-errors --retry-delay 20 --connect-timeout 60 \
                -fsSL "$CONFIGURE_BOARD_PATH/bcm_28xx.sh" -o /tmp/bcm_28xx.sh && bash /tmp/bcm_28xx.sh
        fi
    elif [[ $CPU_MODEL =~ (Raspberry\ Pi\ [4])|(Raspberry\ Pi\ Compute\ Module\ 4.*) ]]; then
        echo "Detected BCM27XX via device tree"
        # 同梱スクリプトを優先使用
        if [ -f "$SCRIPT_DIR/bcm_27xx.sh" ]; then
            bash "$SCRIPT_DIR/bcm_27xx.sh"
        else
            curl --retry 6 --max-time 15 --retry-all-errors --retry-delay 20 --connect-timeout 60 \
                -fsSL "$CONFIGURE_BOARD_PATH/bcm_27xx.sh" -o /tmp/bcm_27xx.sh && bash /tmp/bcm_27xx.sh
        fi
    elif [[ $CPU_MODEL =~ Raspberry\ Pi\ 5 ]]; then
        echo "Detected Raspberry Pi 5 via device tree"
        curl --retry 6 --max-time 15 --retry-all-errors --retry-delay 20 --connect-timeout 60 \
            -fsSL "$CONFIGURE_BOARD_PATH/bcm_2712.sh" -o /tmp/bcm_2712.sh && bash /tmp/bcm_2712.sh
    else
        board_not_detected "/proc/device-tree/model" "$CPU_MODEL"
    fi

elif [ -f "/proc/cpuinfo" ]; then
    CPU_INFO="$(cat /proc/cpuinfo)"
    if [[ $CPU_INFO =~ BCM27[0-9]{2} ]]; then
        echo "Detected BCM27XX via cpuinfo"
        if [ -f "$SCRIPT_DIR/bcm_27xx.sh" ]; then
            bash "$SCRIPT_DIR/bcm_27xx.sh"
        else
            curl --retry 6 --max-time 15 --retry-all-errors --retry-delay 20 --connect-timeout 60 \
                -fsSL "$CONFIGURE_BOARD_PATH/bcm_27xx.sh" -o /tmp/bcm_27xx.sh && bash /tmp/bcm_27xx.sh
        fi
    elif [[ $CPU_INFO =~ BCM28[0-9]{2} ]]; then
        echo "Detected BCM28XX via cpuinfo"
        if [ -f "$SCRIPT_DIR/bcm_28xx.sh" ]; then
            bash "$SCRIPT_DIR/bcm_28xx.sh"
        else
            curl --retry 6 --max-time 15 --retry-all-errors --retry-delay 20 --connect-timeout 60 \
                -fsSL "$CONFIGURE_BOARD_PATH/bcm_28xx.sh" -o /tmp/bcm_28xx.sh && bash /tmp/bcm_28xx.sh
        fi
    else
        board_not_detected "/proc/cpuinfo" "$CPU_INFO"
    fi

else
    echo "Impossible to detect hardware, aborting."
    exit 255
fi
