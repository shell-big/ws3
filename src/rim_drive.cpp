#include "rim_drive.h"
#include <algorithm> // std::max, std::min のため
#include <cmath>     // std::abs のため
#include <stdio.h>   // printf のため

// 前方宣言: thruster_control.cpp 内の set_pwm_channel_duty_cycle を使用するため
// （bindings.h 経由でアクセス）
#include "bindings.h"

// --- ファイルスコープ変数 ---
// 現在の駆動モード（デフォルト: スラスターのみ）
static DriveMode_t current_drive_mode = THRUSTER_ONLY;

// --- ヘルパー関数 ---

// 線形補正関数（rim_drive 専用）
static float rim_map_value(float x, float in_min, float in_max, float out_min, float out_max) {
    if (in_max == in_min) {
        return out_min;
    }
    x = std::max(in_min, std::min(x, in_max));
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

// リムドライブのPWM値をハードウェアに出力するヘルパー
static void set_rim_drive_pwm(int pulse_width_us) {
    // PWM値を Neutral〜Max の範囲にクランプ
    int neutral_pw, max_pw, channel;
    {
        std::lock_guard<std::mutex> lock(g_config_mutex);
        neutral_pw = g_config.rim_drive_pwm_neutral;
        max_pw     = g_config.rim_drive_pwm_max;
        channel    = g_config.rim_drive_channel;
    }

    int clamped_pwm = std::max(neutral_pw, std::min(pulse_width_us, max_pw));

    // デューティサイクルを計算して出力
    float pwm_frequency;
    {
        std::lock_guard<std::mutex> lock(g_config_mutex);
        pwm_frequency = g_config.pwm_frequency;
    }
    float duty_cycle = static_cast<float>(clamped_pwm) / (1000000.0f / pwm_frequency);
    set_pwm_channel_duty_cycle(channel, duty_cycle);
}

// --- モジュール関数 ---

DriveMode_t rim_drive_get_mode() {
    return current_drive_mode;
}

void rim_drive_init() {
    printf("RimDrive: Initializing (mode=THRUSTER_ONLY, channel=%d, neutral=%d)\n",
           g_config.rim_drive_channel, g_config.rim_drive_pwm_neutral);
    current_drive_mode = THRUSTER_ONLY;
    set_rim_drive_pwm(g_config.rim_drive_pwm_neutral);
}

void rim_drive_stop() {
    int neutral_pw;
    {
        std::lock_guard<std::mutex> lock(g_config_mutex);
        neutral_pw = g_config.rim_drive_pwm_neutral;
    }
    set_rim_drive_pwm(neutral_pw);
}

void rim_drive_update(const GamepadData &gamepad_data) {
    // THRUSTER_ONLY モードではリムドライブを出力しない（ニュートラル維持）
    if (current_drive_mode == THRUSTER_ONLY) {
        return;
    }

    int neutral_pw, max_pw, deadzone;
    {
        std::lock_guard<std::mutex> lock(g_config_mutex);
        neutral_pw = g_config.rim_drive_pwm_neutral;
        max_pw     = g_config.rim_drive_pwm_max;
        deadzone   = g_config.joystick_deadzone;
    }

    // 右スティック Y軸（前後スラスターと同軸）を使用
    // スラスターと同様に一方向のみ（デッドゾーン以上の正入力のみ前進）
    int target_pwm = neutral_pw;

    if (gamepad_data.rightThumbY > deadzone) {
        // デッドゾーン〜32767 を neutral〜max にマッピング
        target_pwm = static_cast<int>(
            rim_map_value(static_cast<float>(gamepad_data.rightThumbY),
                          static_cast<float>(deadzone), 32767.0f,
                          static_cast<float>(neutral_pw), static_cast<float>(max_pw)));
    }

    set_rim_drive_pwm(target_pwm);
}

void rim_drive_handle_select_button(const GamepadData &gamepad_data) {
    // Back ボタン (0x0020) の立ち上がりエッジ検出
    static bool select_previously_pressed = false;

    bool select_currently_pressed = (gamepad_data.buttons & GamepadButton::Back);

    if (select_currently_pressed && !select_previously_pressed) {
        // モードを順番に切り替え: THRUSTER_ONLY → RIMDRIVE_ONLY → THRUSTER_RIMDRIVE → THRUSTER_ONLY
        switch (current_drive_mode) {
            case THRUSTER_ONLY:
                current_drive_mode = RIMDRIVE_ONLY;
                printf("DriveMode: RIMDRIVE_ONLY\n");
                break;
            case RIMDRIVE_ONLY:
                current_drive_mode = THRUSTER_RIMDRIVE;
                printf("DriveMode: THRUSTER_RIMDRIVE\n");
                break;
            case THRUSTER_RIMDRIVE:
                current_drive_mode = THRUSTER_ONLY;
                // THRUSTER_ONLY に戻ったらリムドライブをニュートラルに戻す
                rim_drive_stop();
                printf("DriveMode: THRUSTER_ONLY\n");
                break;
        }
    }

    select_previously_pressed = select_currently_pressed;
}
