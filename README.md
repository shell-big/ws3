# ws3 - Navigator Control System 🚀

[![CI](https://github.com/Oryosan59/ws3/actions/workflows/ci.yml/badge.svg)](https://github.com/Oryosan59/ws3/actions/workflows/ci.yml)

リアルタイムセンサ制御・スラスター操作・ゲームパッド入力の統合処理を行う C++ プロジェクトです。BlueRobotics Navigator-lib ライブラリを活用し、ROS などを使用せず軽量で組み込みやすい制御系を構築します。

---

## ✨ 主な機能

- リアルタイムなセンサーデータ（IMU、気圧、水温など）の取得 (※表示・記録は地上局や連携システムに依存)
- ゲームパッドからの入力に基づいたスラスターの精密制御
- ネットワーク経由での遠隔操作指示の受信およびテレメトリデータの送信機能 (※具体的なプロトコルは実装依存)
- モジュール化されたコンポーネント (センサー、ネットワーク、ゲームパッド、スラスター制御)
- 軽量な実装で、Raspberry Piなどのリソースが限られた環境での動作を考慮
- 異常発生時のフェイルセーフ機構 (詳細は後述)

---

## 🛡️ フェイルセーフ機能

本システムには、通信断絶やゲームパッドの接続切れなどの異常事態に備え、以下のフェイルセーフ機能が実装されています。

- **通信断絶時**: 一定時間ゲームパッドや地上局からの入力がない場合、スラスター出力を停止し、安全な状態に移行します。
- **ゲームパッド接続切れ**: ゲームパッドの接続が切れた場合、同様にスラスターを停止します。
- **設定可能なタイムアウト**: フェイルセーフが作動するまでのタイムアウト時間は設定ファイル等で調整可能です。（※ 将来的な拡張または実装詳細を参照）

これにより、予期せぬ状況下でも機体の安全を確保します。

## 🗂️ ディレクトリ構成

```plaintext
ws3/
├── .env                # 環境変数ファイル (ローカル用)
├── .github/            # GitHub Actions ワークフロー
├── .gitignore          # Gitの無視ファイルリスト
├── ARCHITECTURE.md     # アーキテクチャ図・設計ドキュメント
├── config.ini          # 設定ファイル
├── delete.sh           # アンインストールスクリプト
├── Makefile.mk         # Makefile
├── README.md           # このファイル
├── setup.md            # セットアップスクリプトの詳細とトラブルシューティング
├── setup.sh            # 自動セットアップスクリプト
├── include/            # ヘッダーファイル (.h)
│   ├── config_synchronizer.h
│   ├── config.h
│   ├── gamepad.h
│   ├── gstPipeline.h
│   ├── network.h
│   ├── sensor_data.h
│   └── thruster_control.h
├── scripts/            # 初期化・ユーティリティ・オーバーレイスクリプト群
│   ├── configure_board.sh
│   ├── bcm_27xx.sh
│   └── overlays/
├── src/                # ソースファイル (.cpp)
│   ├── config_synchronizer.cpp
│   ├── config.cpp
│   ├── gamepad.cpp
│   ├── gstPipeline.cpp
│   ├── main.cpp
│   ├── network.cpp
│   ├── sensor_data.cpp
│   └── thruster_control.cpp
├── obj/                # (生成) コンパイル済オブジェクトファイル (.o)
└── bin/                # (生成) 実行ファイル
```

### ✅ この構成のメリット
- **役割の分離**：コードとビルド成果物を明確に分けて管理。
- **スケーラビリティ**：モジュール追加時の見通しが良い。
- **クリーンな管理**：`make clean` で obj/bin ディレクトリのみ削除。

---

## � セットアップ（自動）

標準 Raspberry Pi OS 向けのセットアップスクリプトを用意しています。
Rust のインストールから navigator-lib のビルド、systemd サービスの登録まで**全自動**で行います。

```bash
git clone https://github.com/Oryosan59/ws3
cd ws3
chmod +x setup.sh
sudo bash setup.sh
```

> 詳細なトラブルシューティングは [setup.md](./setup.md) を参照してください。

### 🗑️ アンインストール

```bash
sudo bash delete.sh
```

setup.sh が行った変更（サービス停止・navigator-lib 削除・Rust 削除など）を安全に元に戻します。  
ソースコードは削除されないため、`sudo bash setup.sh` で再セットアップできます。

---

## 🛠️ 手動ビルド

### 🔧 前提条件
- g++ (C++11以降) / cmake / GStreamer 1.0
- [BlueRobotics Navigator-lib](https://github.com/bluerobotics/navigator-lib) がビルド済みであること
  （デフォルトでは `~/navigator-lib/target/debug` に配置）

```bash
# navigator-lib のビルド（nightly Rust が必要）
git clone https://github.com/bluerobotics/navigator-lib.git ~/navigator-lib
cd ~/navigator-lib
rustup default nightly
cargo build
```

### 🔄 アプリのビルド

```bash
make -f Makefile.mk
```

> NAVIGATOR_LIB_PATH を変更したい場合:
> ```bash
> make -f Makefile.mk NAVIGATOR_LIB_PATH=/your/custom/path
> ```

### 🔐 リリースビルド（ソース保護付き）

```bash
make -f Makefile.mk release    # ビルド + chmod 600 でソースを保護
make -f Makefile.mk protect    # 保護のみ
make -f Makefile.mk unprotect  # 保護解除（編集時）
```

### 🧹 クリーンアップ

```bash
make -f Makefile.mk clean
```

---

## 🎯 実行ファイル
ビルド成功後、以下の実行ファイルが生成されます：

```bash
./bin/navigator_control
```

---

## 🎮 基本的な使い方

1.  上記の手順に従ってプロジェクトをビルドし、`./bin/navigator_control` を生成します。
2.  必要に応じて、設定ファイル（存在する場合）を編集し、ネットワーク設定や制御パラメータを調整します。
3.  `./bin/navigator_control` を実行します。
    ```bash
    ./bin/navigator_control
    ```
4.  地上局ソフトウェア（別途準備または開発）を起動し、本システムが動作するデバイスのIPアドレス・ポートに接続します。
5.  対応するゲームパッドをPCまたはRaspberry Piに接続します。
6.  ゲームパッドの入力に応じてスラスターが制御され、センサーデータが地上局に送信されることを確認します。

> **注記:**
> - 具体的なゲームパッドのボタン割り当てや、地上局との通信プロトコルの詳細は、ソースコード内のコメントや関連ドキュメントを参照してください。
> - 初回実行時やハードウェア構成変更後は、キャリブレーションや動作テストを慎重に行ってください。

---

## ⚙️ 設定ファイル (config.ini) の詳細

このアプリケーションの動作は `config.ini` ファイルによって詳細にカスタマイズ可能です。以下に各パラメータの役割と、関連する計算式をコードに基づいて説明します。

--- 

### `[PWM]`
**役割:** スラスターやLEDを駆動するPWM信号の基本特性を定義します。
**参照コード:** `src/thruster_control.cpp`

- `PWM_MIN`
  - **説明:** スラスターの完全停止状態を示すPWM値（マイクロ秒）。安全のための最小出力値としても機能します。
  - **コード上の動作:** `set_thruster_pwm()`関数内で、すべての出力はこの値を下回らないようにクランプ（制限）されます。通信切断時のフェイルセーフでは、全スラスターがこの値に設定されます。

- `PWM_NEUTRAL`
  - **説明:** 推力ゼロの中立点を定義します。
  - **コード上の動作:** 現在のコードでは直接的な計算に使用されていません。ジョイスティックの`DEADZONE`が実質的な中立帯として機能します。

- `PWM_NORMAL_MAX`
  - **説明:** 通常操作時（ブーストなし）に出力される最大のPWM値。
  - **コード上の動作:** ジョイスティックの入力をPWM値に変換する際の最大値として使用されます。

- `PWM_BOOST_MAX`
  - **説明:** ブースト機能使用時の最大PWM値、およびシステム全体の絶対的な出力上限。
  - **コード上の動作:** 
    1.  特定のスティック操作の組み合わせ（例：旋回＋平行移動）が検出された際、出力が`PWM_NORMAL_MAX`からこの値まで引き上げられます。
    2.  `set_thruster_pwm()`関数内で、すべてのPWM出力がこの値を超えないようにクランプされ、ハードウェアを保護します。

- `PWM_FREQUENCY`
  - **説明:** PWM信号の周波数（Hz）。
  - **コード上の動作:** `thruster_init()`関数で一度だけハードウェアに設定されます。接続されているESC（電子速度コントローラー）の仕様に合わせる必要があります。

--- 

### `[THRUSTER_CONTROL]`
**役割:** ジョイスティックの操作性や、ジャイロセンサーを利用した自動姿勢補正の挙動を決定します。
**参照コード:** `src/thruster_control.cpp`

- `SMOOTHING_FACTOR_HORIZONTAL` / `SMOOTHING_FACTOR_VERTICAL`
  - **説明:** 値が0に近いほど、機体の動きが滑らかになります。
  - **コード上の動作:** スラスターの目標PWM値が急に変化しないように、現在の値と目標値の間を補間します。
  - **計算式:** 
    ```
    新しいPWM値 = 現在のPWM値 + (目標のPWM値 - 現在のPWM値) * SMOOTHING_FACTOR
    ```

- `KP_ROLL` / `KP_YAW`
  - **説明:** 機体の傾き（ロール）や向きの変化（ヨー）を自動補正する際の強さを決める比例ゲイン。
  - **コード上の動作:** ジャイロセンサーが検出した角速度にこのゲインを乗算し、補正用のPWM値を算出します。
  - **計算式:** 
    ```
    補正PWM値 = ジャイロが検出した角速度 * KP
    ```
    この`補正PWM値`が各スラスターの出力に加算・減算され、機体を安定させます。

- `YAW_THRESHOLD_DPS`
  - **説明:** ヨー安定化制御が作動を開始する角速度のしきい値（deg/sec）。
  - **コード上の動作:** 意図しない微小な回転（センサーノイズなど）で制御が過敏に反応するのを防ぎます。ヨー角速度の絶対値がこの値を超えた場合にのみ、安定化制御が働きます。

- `YAW_GAIN`
  - **説明:** ヨー安定化制御の全体的な強さ。
  - **コード上の動作:** しきい値を超えたヨー角速度にこのゲインが乗算され、最終的な補正PWM値が計算されます。

--- 

### `[JOYSTICK]`
**役割:** ジョイスティックの入力特性を定義します。
**参照コード:** `src/thruster_control.cpp`

- `DEADZONE`
  - **説明:** スティック中央の遊び（ニュートラルゾーン）の範囲。
  - **コード上の動作:** スティックの入力値（-32768〜32767）の絶対値がこの値を下回る場合、入力は「0」と見なされ、スラスターは反応しません。推力は、入力がこの値を超えた範囲で計算されます。
  - **計算式（推力マッピング）:** 
    ```
    PWM値 = map_value(入力値, DEADZONE, 32767, PWM_MIN, PWM_NORMAL_MAX)
    ```
    ※`map_value`は、ある範囲の数値を別の範囲の数値に線形変換する関数です。

--- 

### `[LED]` / `[LED2]`
**役割:** LEDの点灯・消灯を制御します。
**参照コード:** `src/thruster_control.cpp`

- `CHANNEL`
  - **説明:** LEDが接続されているPWMチャンネル番号。
- `ON_VALUE` / `OFF_VALUE` / `MAX_VALUE`
  - **説明:** LEDの各状態（点灯、消灯、最大光量など）に対応するPWM値。
  - **コード上の動作:** ゲームパッドの特定ボタン（Y, B）が押されると、コードはこれらの値を参照して対応する`CHANNEL`にPWM信号を出力し、LEDの状態を切り替えます。

--- 

### `[NETWORK]`
**役割:** 操縦PCとのUDP通信に関する設定です。
**参照コード:** `src/network.cpp`, `src/main.cpp`

- `RECV_PORT`: **データ受信ポート**。ジョイスティックのデータなどをPCから受信するために、このポートで待ち受けます。
- `SEND_PORT`: **データ送信ポート**。センサーデータなどをPCへ送信する際に、この宛先ポート番号を使用します。
- `CLIENT_HOST`: **通信相手のIPアドレス**。
  - **コード上の動作:** 
    1.  **セキュリティ:** このIPアドレス以外から受信したパケットは破棄されます（`0.0.0.0`は任意許可）。
    2.  **宛先指定:** センサーデータを送信する際の宛先IPアドレスとして使用されます。
- `CONNECTION_TIMEOUT_SECONDS`: **接続タイムアウト（秒）**。
  - **コード上の動作:** PCからのデータ受信がこの秒数以上途絶えると、通信が切断されたと判断し、全スラスターを停止させるフェイルセーフが作動します。

--- 

### `[APPLICATION]`
**役割:** アプリケーション本体の動作周期や通信頻度を制御します。
**参照コード:** `src/main.cpp`

- `SENSOR_SEND_INTERVAL`: **センサーデータの送信頻度**。メインループがこの設定値の回数実行されるたびに、1回センサーデータがPCへ送信されます。
- `LOOP_DELAY_US`: **メインループの待機時間（マイクロ秒）**。ループの各サイクルの最後にこの時間だけ待機処理を入れ、CPU負荷を下げると共に、全体の動作タイミングを安定させます。

--- 

### `[GSTREAMER_CAMERA_1]` / `[GSTREAMER_CAMERA_2]`
**役割:** GStreamerを利用したカメラ映像のネットワーク配信設定です。
**参照コード:** `src/gstPipeline.cpp`

- `DEVICE`: **カメラのデバイスパス**（例: `/dev/video2`）。
- `PORT`: **映像配信先のUDPポート番号**。
- `WIDTH` / `HEIGHT`: **映像の解像度**。
- `FRAMERATE_NUM` / `FRAMERATE_DEN`: **映像のフレームレート**。
- `IS_H264_NATIVE_SOURCE`:
  - **説明:** カメラがH.264形式で直接映像を出力できるかどうかのフラグ。
  - **コード上の動作:** 
    - `true`の場合: `v4l2src -> h264parse -> ...` という軽量なパイプラインを構築します。ハードウェアエンコーダを利用するため、CPU負荷が低いのが特徴です。
    - `false`の場合: `v4l2src -> jpegdec -> videoconvert -> x264enc -> ...` という、CPUでH.264へのエンコード処理（ソフトウェアエンコード）を行うパイプラインを構築します。
- `X264_...` (BITRATE, TUNE, SPEED_PRESET): `IS_H264_NATIVE_SOURCE=false` の場合にのみ使用され、ソフトウェアエンコーダ`x264enc`の画質や速度を調整します。

--- 


## 🤖 サービスの自動起動 (systemd)

`setup.sh` を使用してセットアップした場合、systemd サービスは自動的に設定されます。

```bash
# 状態確認
sudo systemctl status navigator_control.service

# リアルタイムログ
journalctl -u navigator_control.service -f

# 手動停止 / 再起動
sudo systemctl stop navigator_control.service
sudo systemctl restart navigator_control.service
```

---

## 🔁 CI (GitHub Actions)

| ジョブ | ランナー | 内容 |
|---|---|---|
| `ShellCheck` | ubuntu-latest | setup.sh / delete.sh の文法チェック |
| `Build (ARM64)` | ubuntu-24.04-arm | navigator-lib + アプリを ARM64 でフルビルド |

Push / PR 時に自動実行されます。ステータスはページ上部のバッジで確認できます。

---

## 🔌 外部ライブラリ

- [BlueRobotics Navigator-lib](https://github.com/bluerobotics/navigator-lib)  
  センサ・PWM出力・スラスター制御を行うためのRustベースライブラリ（C/C++バインディングを使用）  
  ⚠️ **nightly Rust が必須**（`cpy-binder` が `-Zunpretty=expanded` を使用するため）

---

## 🎁 オマケ：Navigator-lib & Flight Controller のセットアップガイド

このプロジェクトで使用している [BlueRobotics Navigator-lib](https://github.com/bluerobotics/navigator-lib) のバインディング構築方法と、Raspberry Pi 上で Navigator Flight Controller を使うための準備手順を紹介します🛠️✨

---

### 🧱 1. Raspberry Pi Imager のインストール

#### 1.1 Raspberry Pi Imager の入手
- [公式サイト](https://www.raspberrypi.com/software/)から、お使いのOSに対応するバージョンをダウンロード＆インストールしてください。

---

### 💿 2. Raspberry Pi OS イメージの準備

#### 2.1 OSイメージの選定（Lite推奨）
以下のいずれかを選びます。

| アーキテクチャ | ファイル名 | サイズ | ダウンロードリンク |
|----------------|------------|--------|------------------|
| 32-bit (armhf) | 2023-02-21-raspios-bullseye-armhf-lite.img.xz | 約362MB | [DLリンク](https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2023-02-22/) |
| 64-bit (arm64) | 2023-02-21-raspios-bullseye-arm64-lite.img.xz | 約307MB | [DLリンク](https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2023-02-22/) |

![Image](https://github.com/user-attachments/assets/a0fb8328-bb0a-4a6b-b84a-f3993df9bd4e)
一番上を選択します

### 2.2 Raspberry Pi Imager で microSD にフラッシュ
1. Imager を起動し、上記でダウンロードしたイメージを選択

    ![Image](https://github.com/user-attachments/assets/c4475b9c-18ef-4990-a089-462760b79c10)
    ![Image](https://github.com/user-attachments/assets/0fea632b-a403-4720-b0ea-051ba5aef1e5)

2. 設定を編集するをクリックして以下を設定：
   - ホスト名、ユーザー名、パスワードの設定
   - Wi-Fi設定（SSIDとパスワード入力。**ステルスSSIDのチェックは外す**）
   - ロケール：
     - タイムゾーン：Asia/Tokyo
     - キーボードレイアウト：jp
   - サービス：SSH を有効化


    ![Image](https://github.com/user-attachments/assets/b457e316-caff-48e7-82dc-f9ec5a33a81a)
    ![Image](https://github.com/user-attachments/assets/92d853b0-1c52-42b7-bb09-f8303e310996)

3. microSD に書き込み開始

---

## 🌐 3. ネットワーク設定
MicroHDMIとキーボードをラズパイに接続し、操作します


### 3.1 固定IP設定（有線LAN）
```bash
sudo nano /etc/dhcpcd.conf
```
ファイル最下部に追記：
```conf
interface eth0
static ip_address=192.168.4.100/24
```
記入が終わったら、終了する: `Ctrl + X`（「Exit」）
「Save modified buffer?」と表示されるので、`Y`（Yes）を押して保存します

---

## 🖥️ 4. Tera Term / ターミナルでの有線SSH接続

### ⚙️ 前提条件
- Raspberry PiとPCをLANケーブルで接続（スイッチングハブ経由または直接接続）
- Raspberry Piに固定IPを設定済み（例: `192.168.4.100`）

---

### 🪟 4.1 Windows：Tera Term で接続する

#### 4.1.1 Tera Term のインストール
1. 公式サイトから Tera Term をダウンロード:  
   [https://ttssh2.osdn.jp/](https://ttssh2.osdn.jp/)
2. インストーラーを実行してインストール

#### 4.1.2 接続手順
1. Tera Term を起動
2. 「ホスト」欄に Raspberry Pi のIPアドレス（例: `192.168.4.100`）を入力
3. 「SSH」を選択し、OKをクリック
4. ユーザー名とパスワードを入力してログイン（例: `pi / raspberry`）

✅ 接続に成功すると、Raspberry Pi のシェル画面が表示されます。

---

### 🍎 4.2 macOS：ターミナルでSSH接続する

#### 4.2.1 標準ターミナルを使用
1. 「ターミナル」アプリを開く（`Command + Space` → "terminal" と入力）
2. 以下のコマンドで接続：

```bash
ssh pi@192.168.1.100
```

3. 最初の接続時に表示される fingerprint の確認メッセージで「yes」と入力
4. パスワードを入力（表示されないが打ててます）

✅ ログインに成功すると、ターミナルに `pi@raspberrypi` のプロンプトが表示されます。

---

### 💡 補足：接続できないときのチェックポイント
- Raspberry Pi の電源が入っているか
- LANケーブルが確実に接続されているか
- Raspberry Pi 側のIPアドレスが正しいか（`ifconfig` または `ip a` で確認可能）
- ファイアウォールの影響がないか

---

## 🌐 5. Windows / macOS での有線LAN固定IP設定ガイド

Raspberry PiとPCをLANケーブルで**直接接続**または**ハブ経由でローカル接続**する場合、お互いのIPアドレスを固定にする必要があります
ここでは、**Raspberry PiのIPを `192.168.4.100` に固定**する前提で、**PC側を `192.168.4.10`** に設定する方法を解説します

---

### 🪟 5.1 Windowsでの設定方法

#### 📌 手順
1. **[設定] → [ネットワークとインターネット] → [アダプターのオプションを変更する]** を開く
2. 有線LAN（例:「イーサネット」）を**右クリック → [プロパティ]**
3. 「インターネットプロトコル バージョン4 (TCP/IPv4)」を選択し**[プロパティ]**
4. 以下のように設定：

| 項目 | 設定内容 |
|------|----------|
| IPアドレス | `192.168.4.10` |
| サブネットマスク | `255.255.255.0` |
| デフォルトゲートウェイ | （空白でOK） |
| DNS | （空白または `8.8.8.8`） |

5. [OK] をクリックして設定を保存

✅ 接続後、Tera Termで `192.168.4.100` にSSH可能になるはずです

---

### 🍎 5.2 macOSでの設定方法

#### 📌 手順
1. **[システム設定] → [ネットワーク]** を開く
2. 左メニューから「有線Ethernet」または「USB LANアダプタ」を選択
3. 「詳細」→ 「TCP/IP」タブを開く
4. 「IPv4の設定」→「手入力（Manually）」を選択
5. 以下を入力：

| 項目 | 設定内容 |
|------|----------|
| IPアドレス | `192.168.4.10` |
| サブネットマスク | `255.255.255.0` |
| ルーター | 空白（または `192.168.1.1`） |

6. [OK] → [適用] をクリック

✅ ターミナルで `ssh pi@192.168.4.100` で接続可能になります

---

### 🧪 接続テスト

PCから以下のように Raspberry Pi に ping を送って確認します：

```bash
ping 192.168.4.100
```

`応答があります` や `bytes from 192.168.4.100` のような表示が出れば、接続成功です！

---


## 🛠️ 6. 必要なツールのインストール
接続後、ターミナルで実行します

```bash
sudo apt update
sudo apt install git i2c-tools
```

---

## 🧭 7. Navigator ハードウェアのセットアップ
 [BlueRobotics Navigator-lib](https://github.com/bluerobotics/navigator-lib)   のバインディング構築方法と、Raspberry Pi 上で Navigator Flight Controller を使うための準備手順を紹介します
 
### 7.1 オーバーレイ設定スクリプトの実行
本プロジェクトにはオーバーレイスクリプトが同梱されており、セキュアに設定を行えます。
（※ `setup.sh` を使用してセットアップした場合は、この手順は自動実行されるためスキップ可能です。）

```bash
sudo su -c 'curl -fsSL https://raw.githubusercontent.com/bluerobotics/blueos-docker/master/install/boards/configure_board.sh | bash'
sudo reboot
```

---

## 🧪 8. Navigator-lib のビルドと実行

### 8.1 依存パッケージのインストール
```bash
sudo apt install cmake git
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

### 8.2 ライブラリの取得とビルド
```bash
git clone https://github.com/bluerobotics/navigator-lib.git
cd navigator-lib/examples/cpp
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --config Debug --parallel
```
> **備考**: C++バインディングのビルド結果は `navigator-lib/target/debug` に配置されるため、`Makefile` で `NAVIGATOR_LIB_PATH` にこのパスを指定して利用します。

### 8.3 サンプルの実行
```bash
./build/simple
./build/rainbow
```

以上で、Raspberry Pi 4B + Navigator-lib の準備が完了です！💡

---

## 🧭 作者

**Oryosan59**  
https://github.com/Oryosan59
