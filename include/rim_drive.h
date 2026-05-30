#ifndef RIM_DRIVE_H // インクルードガード
#define RIM_DRIVE_H

#include "gamepad.h" // GamepadData 構造体の定義が必要なためインクルード
#include "config.h"  // グローバル設定オブジェクト g_config を使用するため

// --- 駆動モード定義 ---
typedef enum
{
    THRUSTER_ONLY,      // スラスターのみ有効
    RIMDRIVE_ONLY,      // リムドライブのみ有効（スラスターは pwm_min 固定）
    THRUSTER_RIMDRIVE   // スラスター＋リムドライブ 両方有効
} DriveMode_t;

// --- 関数プロトタイプ宣言 ---

// 現在の駆動モードを取得する
DriveMode_t rim_drive_get_mode();

// リムドライブを初期化する（ニュートラルPWMを出力）
void rim_drive_init();

// リムドライブをニュートラルに停止する（pwm_neutral 出力）
void rim_drive_stop();

// ゲームパッド入力からリムドライブPWMを更新する
// 現在の駆動モードが RIMDRIVE_ONLY または THRUSTER_RIMDRIVE の場合のみ出力する
void rim_drive_update(const GamepadData &gamepad_data);

// Selectボタン（Back）によるモード切替処理
// thruster_update() 内から毎フレーム呼び出す
void rim_drive_handle_select_button(const GamepadData &gamepad_data);

#endif // RIM_DRIVE_H
