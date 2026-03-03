# setup.sh 作成記録 & トラブルシューティング

ws3 Navigator Control System を標準 Raspberry Pi OS 上でセットアップするスクリプト `setup.sh` の作成記録。  
発生したエラーと解決策をすべて記録する。

---

## setup.sh の概要

| ステップ | 内容 |
|---|---|
| 1 | システムパッケージのインストール（cmake / build-essential / i2c-tools 等） |
| 2 | Rust / Cargo（rustup）のインストール |
| 3 | I2C / SPI / GPIO ハードウェアインターフェースの有効化 |
| 4 | navigator-lib（BlueRobotics）のクローン & ビルド |
| 5 | GStreamer のインストール |
| 6 | アプリケーション本体のビルド（make -f Makefile.mk） |
| 7 | systemd サービスの登録・自動起動設定 |

---

## トラブルシューティング一覧

---

### ❶ navigator-lib のクローンで Permission denied

**エラー:**
```
fatal: could not create work tree dir '/root/navigator-lib': Permission denied
```

**原因:**  
`NAVIGATOR_LIB_DIR="$HOME/navigator-lib"` としていたが、  
`sudo bash setup.sh` で実行すると `$HOME` が `/root`（root のホーム）に展開されてしまう。  
その後 `sudo -u pi` でクローンしようとして、`/root/` への書き込み権限がなくエラー。

**解決策:**  
`$HOME` の代わりに明示的なパスを使用する。

```diff
- NAVIGATOR_LIB_DIR="$HOME/navigator-lib"
+ INSTALL_USER="${SUDO_USER:-pi}"
+ USER_HOME="/home/${INSTALL_USER}"
+ NAVIGATOR_LIB_DIR="${USER_HOME}/navigator-lib"
```

---

### ❷ cargo で `edition 2024` パースエラー

**エラー:**
```
failed to parse the `edition` key
this version of Cargo is older than the `2024` edition,
and only supports `2015`, `2018`, and `2021` editions.
```

**原因:**  
`navigator-rs` の依存クレート `getrandom v0.4.1` が `edition = "2024"` を使用。  
`sudo -u pi bash -c` 実行時に `sudo` の `secure_path` 設定で PATH がリセットされ、  
`/usr/bin/cargo`（Debian の apt 版・古い）が使われてしまっていた。

**解決策:**  
cargo をフルパスで指定してシステムの古い cargo を回避。  
さらに `~/.cargo/bin/cargo`（rustup シム）ではなく、  
実際のツールチェーンバイナリ `~/.rustup/toolchains/<name>/bin/cargo` を直接参照。

```bash
TOOLCHAIN_NAME=$(run_as_user "$RUSTUP_BIN" toolchain list | grep nightly | head -1 | awk '{print $1}')
ACTUAL_CARGO="${USER_HOME}/.rustup/toolchains/${TOOLCHAIN_NAME}/bin/cargo"
```

---

### ❸ `could not execute process 'rustc -vV'`

**エラー:**
```
error: could not execute process `rustc -vV` (never executed)
Caused by:
  No such file or directory (os error 2)
```

**原因:**  
`sudo -u pi` は `HOME=/root` を引き継ぐため、  
cargo が rustup のツールチェーンディレクトリ `~/.rustup/toolchains/` を発見できず、  
`rustc` を実行しようとして失敗。

**解決策:**  
`run_as_user()` ヘルパー関数を導入し、すべてのユーザー権限コマンドで  
`HOME` / `RUSTUP_HOME` / `CARGO_HOME` / `PATH` を明示的に設定。  
ツールチェーンの `bin/` も PATH に追加して `rustc` を解決。

```bash
run_as_user() {
  sudo -H -u "$INSTALL_USER" \
    env HOME="${USER_HOME}" \
        RUSTUP_HOME="${USER_HOME}/.rustup" \
        CARGO_HOME="${USER_HOME}/.cargo" \
        PATH="${USER_HOME}/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$@"
}
```

ビルド時はツールチェーンの `bin/` も PATH に追加：

```bash
run_as_user \
  env PATH="${TOOLCHAIN_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  bash -c "cd '${NAVIGATOR_LIB_DIR}' && '${ACTUAL_CARGO}' build"
```

---

### ❹ build.rs パニック: `Unable to generate bindings: CargoExpand`

**エラー:**
```
error: the option `Z` is only accepted on the nightly compiler
help: consider switching to a nightly toolchain: `rustup default nightly`
```

**原因:**  
`bluerobotics_navigator` の `build.rs` が使う `cpy-binder` クレートが  
内部で `-Zunpretty=expanded` フラグ（**nightly 専用**）を使用している。  
stable Rust ではこのフラグが使えないためビルド不可。

**解決策:**  
Rust ツールチェーンを `stable` から `nightly` に切り替える。

```bash
run_as_user "$RUSTUP_BIN" toolchain install nightly
run_as_user "$RUSTUP_BIN" default nightly
```

> ⚠️ `navigator-lib v0.1.2` は **nightly Rust が必須**。stable では絶対にビルドできない。

---

### ❺ パッケージ `libgpiod2` が見つからない

**エラー:**
```
E: Unable to locate package libgpiod2
```

**原因:**  
Debian Trixie（Raspberry Pi OS の現在のベース）に `libgpiod2` パッケージが存在しない。  
（`libgpiod3` に名称が変わっている）

**解決策:**  
`libgpiod2` をパッケージリストから削除。`libgpiod-dev` のみインストールする。

```diff
  libgpiod-dev
- libgpiod2
```

---

### ❻ サービス起動時クラッシュ: `Failed to create Icm20689`

**エラー（journalctl）:**
```
panicked at navigator-rs-0.6.0/src/lib.rs:447:22:
Failed to create Icm20689: Os { code: 2, kind: NotFound, message: "No such file or directory" }
```

**原因:**  
`navigator-rs` の初期化時に I2C バス経由で ICM-20689（IMU センサー）を探すが、  
`/dev/i2c-1` が存在しないためパニック → Rust の FFI パニックが SIGABRT になる。

考えられる要因：
- `dtparam=i2c_arm=on` を書いたが **再起動していない**
- Navigator ボードが **物理的に未接続**

**確認コマンド:**
```bash
ls /dev/i2c*           # /dev/i2c-1 がなければ再起動が必要
sudo i2cdetect -y 1   # 0x40 (PCA9685) が表示されれば Navigator 認識済み
```

**解決策:**
1. I2C 有効化後に `sudo reboot`
2. Navigator ボードが正しくコネクタに挿さっているか確認

---

## 重要なポイントまとめ

| ポイント | 内容 |
|---|---|
| `sudo` での `$HOME` | `sudo bash` 実行時は `$HOME=/root` になる。`SUDO_USER` を使って実際のユーザーのホームを取得すること |
| `secure_path` | `sudo` は PATH をリセットする。コマンドはフルパスで指定するか `env PATH=...` で上書きが必要 |
| `HOME` の継承 | `sudo -u pi` は HOME を引き継がない。`sudo -H -u pi` または `env HOME=...` が必要 |
| Rust nightly 必須 | `navigator-lib v0.1.2` は `cpy-binder` の都合で nightly Rust が必須 |
| I2C は再起動が必要 | `dtparam=i2c_arm=on` を `/boot/firmware/config.txt` に書いても再起動しないと `/dev/i2c-1` は生成されない |

---

## 関連ファイル

| ファイル | 役割 |
|---|---|
| [`setup.sh`](./setup.sh) | セットアップスクリプト（本番用） |
| [`delete.sh`](./delete.sh) | アンインストールスクリプト（setup.sh の変更を元に戻す） |
| [`Makefile.mk`](./Makefile.mk) | ビルドスクリプト（`make release` でソース保護付きビルド） |
| [`config.ini`](./config.ini) | アプリケーション設定（PWM・ネットワーク・カメラ等） |
| [`scripts/configure_board.sh`](./scripts/configure_board.sh) | Navigator ボード初期化スクリプト（同梱版） |
| [`scripts/bcm_27xx.sh`](./scripts/bcm_27xx.sh) | Pi 4B 専用オーバーレイ設定（同梱版） |
| [`scripts/overlays/spi0-led.dts`](./scripts/overlays/spi0-led.dts) | Neopixel LED 用 SPI0 デバイスツリーオーバーレイ（同梱版） |

---

## Navigator オーバーレイスクリプトのセキュリティ対策

### 背景: `curl | bash` の問題

BlueRobotics 公式の Navigator ボード初期化手順では以下のコマンドを使用する:

```bash
# 公式手順（使用しない）
sudo su -c 'curl -fsSL https://raw.githubusercontent.com/bluerobotics/blueos-docker/master/install/boards/configure_board.sh | bash'
```

このパターンには以下のリスクがある:

| リスク | 説明 |
|---|---|
| 中間者攻撃 (MITM) | ダウンロードと実行が一体のため、改ざんされたスクリプトが即座に root 権限で実行される |
| リポジトリ侵害 | master ブランチへの予期しない変更が翌日のセットアップから即反映される |
| 事後検証不可 | 何が実行されたのか後からトレースできない |

### 採用した対策: スクリプト同梱

`curl` 依存を完全に廃止し、**スクリプトをリポジトリに同梱してローカルから実行**している。

```
scripts/
├── configure_board.sh      ← Pi のモデル判定・ボード別スクリプトの振り分け
├── bcm_27xx.sh             ← Pi 4B (BCM27XX) 専用のオーバーレイ設定
└── overlays/
    └── spi0-led.dts        ← Neopixel LED 用 SPI0 デバイスツリーオーバーレイ
```

`setup.sh` からは以下のように呼び出す:

```bash
bash "${PROJECT_DIR}/scripts/configure_board.sh"
```

#### `configure_board.sh` の内部構造

スクリプトがボードを判定し、対応するサブスクリプトをローカルから呼び出す:

```
/proc/device-tree/model を読む
  ├── Raspberry Pi [0-3] → scripts/bcm_28xx.sh (同梱なければ未サポート)
  ├── Raspberry Pi 4     → scripts/bcm_27xx.sh ← Pi 4B はここ
  └── Raspberry Pi 5     → bcm_2712.sh (未同梱)
```

#### `bcm_27xx.sh` が行う設定（Pi 4B 専用）

| 設定内容 | 詳細 |
|---|---|
| SPI0 オーバーレイコンパイル | `spi0-led.dts` を `dtc` でコンパイルし `/boot/overlays/` に配置 |
| `[pi4]` セクション追加 | `/boot/config.txt` に Pi 4 専用セクションを追加 |
| UART 有効化 | uart1 / uart3 / uart4 / uart5 の dtoverlay 追加 |
| I2C 有効化 | i2c1 / i2c4 / i2c6 を baudrate 指定付きで有効化 |
| SPI 有効化 | spi0-led / spi1-3cs のオーバーレイ追加 |
| GPIO 設定 | Navigator ボード用ピン設定（11, 24, 25, 37） |
| カーネルモジュール | `bcm2835-v4l2` / `i2c-bcm2835` / `i2c-dev` を `/etc/modules` に追加 |
| シリアル | `cmdline.txt` からシリアルコンソール設定を除去 |
| cgroup 有効化 | cpuset / memory の cgroup を cmdline に追加 |
| USB OTG | dwc2 / g_ether を有効化 |
| ファームウェア更新 | Bullseye のみ: rpi-update で固定バージョンに更新 |

> ⚠️ 上記の設定はすべて **再起動後に反映**される。  
> `setup.sh` 完了後に必ず `sudo reboot` を実行すること。

---

## アップストリーム追従

「アップストリーム追従」とは、**BlueRobotics 本家リポジトリが更新されたとき、同梱スクリプトに手動で反映する作業**のこと。  
スクリプトを同梱した副作用として、本家の更新が自動では反映されなくなる。

### 追従が必要になるタイミング

- 新しい Raspberry Pi ハードウェアへの対応（Pi 5 / 6 等）
- Raspberry Pi OS の新バージョン（Bookworm の次等）での設定変更
- Navigator ボードのハードウェアリビジョン変更

### 手順

1. **本家の最新版を確認する**

   ```bash
   # ブラウザで差分を確認
   # https://github.com/bluerobotics/blueos-docker/commits/master/install/boards/
   ```

2. **ファイルをダウンロードして差分確認**

   ```bash
   curl -fsSL https://raw.githubusercontent.com/bluerobotics/blueos-docker/master/install/boards/configure_board.sh \
     -o /tmp/configure_board_upstream.sh

   diff scripts/configure_board.sh /tmp/configure_board_upstream.sh
   ```

3. **独自変更を保持しながら更新する**

   同梱版には以下の独自変更が加えられているため、単純な上書きではなく差分を確認して取り込む:

   | 変更箇所 | 内容 |
   |---|---|
   | `configure_board.sh` | `curl \| bash` → `bash "$SCRIPT_DIR/bcm_27xx.sh"` に変更 |
   | `bcm_27xx.sh` | `spi0-led.dts` を curl 取得 → ローカルファイル参照に変更 |

4. **動作確認後にコミット**

   ```bash
   git add scripts/
   git commit -m "chore: 🔧 BlueRobotics スクリプトをアップストリームに追従"
   ```
