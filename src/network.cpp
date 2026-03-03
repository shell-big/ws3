#include "network.h"
#include "config.h" // g_config を使用するため
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h> // gettimeofday のため
#include <unistd.h>

// ネットワーク送受信コンテキストを初期化する関数
bool network_init(NetworkContext *ctx) {
  if (!ctx)
    return false; // コンテキストポインタが無効なら失敗

  // 設定オブジェクトからポート番号を取得
  int recv_port = g_config.network_recv_port;
  int send_port = g_config.network_send_port;

  // コンテキスト初期化
  memset(ctx, 0, sizeof(NetworkContext));
  ctx->recv_socket = -1;
  ctx->send_socket = -1;
  ctx->client_addr_len = sizeof(ctx->client_addr_recv);
  ctx->client_addr_known = false;
  gettimeofday(&ctx->last_successful_recv_time, NULL); // 現在時刻で初期化

  // --- 受信ソケット設定 ---
  ctx->recv_socket = socket(AF_INET, SOCK_DGRAM, 0);
  if (ctx->recv_socket < 0) {
    perror("受信ソケット作成失敗");
    return false;
  }

  // ノンブロッキング設定
  int flags = fcntl(ctx->recv_socket, F_GETFL, 0);
  if (flags == -1 || fcntl(ctx->recv_socket, F_SETFL, flags | O_NONBLOCK) ==
                         -1) // 現在のフラグを取得し、O_NONBLOCK を追加
  {
    perror("受信ソケットのノンブロッキング設定失敗");
    close(ctx->recv_socket);
    ctx->recv_socket = -1;
    return false;
  }

  // サーバー（このプログラム）のアドレス情報を設定
  memset(&ctx->server_addr, 0, sizeof(ctx->server_addr));
  ctx->server_addr.sin_family = AF_INET;
  ctx->server_addr.sin_addr.s_addr = INADDR_ANY;
  ctx->server_addr.sin_port = htons(recv_port);

  // ソケットにアドレス情報を割り当て (バインド)
  if (bind(ctx->recv_socket, (const struct sockaddr *)&ctx->server_addr,
           sizeof(ctx->server_addr)) < 0) {
    perror("受信ソケットのバインド失敗");
    close(ctx->recv_socket);
    ctx->recv_socket = -1;
    return false;
  }
  printf("UDPサーバー起動 (受信ポート: %d)\n", recv_port);

  // --- 送信ソケット設定 ---
  ctx->send_socket = socket(AF_INET, SOCK_DGRAM, 0);
  if (ctx->send_socket < 0) {
    perror("送信ソケット作成失敗");
    close(ctx->recv_socket); // 受信ソケットも閉じる
    ctx->recv_socket = -1;
    return false;
  }

  // 送信先アドレスの初期設定 (ポートのみ)
  memset(&ctx->client_addr_send, 0, sizeof(ctx->client_addr_send));
  ctx->client_addr_send.sin_family = AF_INET;
  ctx->client_addr_send.sin_port = htons(
      send_port); // 送信ポート番号を設定 (ネットワークバイトオーダーに変換)
  // 送信先IPアドレスは最初の受信時に設定される

  printf("UDP送信準備完了 (送信先ポート: %d)\n", send_port);
  return true;
}

// ネットワーク関連のリソースを解放する関数
void network_close(NetworkContext *ctx) {
  if (ctx) {
    if (ctx->recv_socket >= 0) {
      close(ctx->recv_socket);
      ctx->recv_socket = -1;
    }
    if (ctx->send_socket >= 0) {
      close(ctx->send_socket);
      ctx->send_socket = -1;
    }
    printf("ソケットをクローズしました。\n");
  }
}

// UDPデータを受信する関数 (ノンブロッキング)
ssize_t network_receive(NetworkContext *ctx, char *buffer, size_t buffer_size) {
  if (!ctx || ctx->recv_socket < 0 || !buffer || buffer_size == 0) {
    return -1; // 引数が無効ならエラー
  }

  ssize_t final_recv_len = -1;
  bool valid_packet_received = false;
  static struct timeval last_warning_time = {0, 0};

  // OSの受信バッファに溜まっているパケットをすべて読み切るループ (ドレイン)
  while (true) {
    ctx->client_addr_len = sizeof(ctx->client_addr_recv);

    // recvfrom は O_NONBLOCK により、データがない場合は -1 (errno = EAGAIN)
    // を返す
    ssize_t current_recv_len = recvfrom(
        ctx->recv_socket, buffer, buffer_size - 1, 0,
        (struct sockaddr *)&ctx->client_addr_recv, &ctx->client_addr_len);

    if (current_recv_len > 0) {
      // --- セキュリティチェック: 許可されたIPアドレスからのパケットか検証 ---
      char client_ip_str[INET_ADDRSTRLEN];
      inet_ntop(AF_INET, &ctx->client_addr_recv.sin_addr, client_ip_str,
                INET_ADDRSTRLEN);

      // 安全に設定値を取得する
      std::string client_host_val;
      {
        std::lock_guard<std::mutex> lock(g_config_mutex);
        client_host_val = g_config.client_host;
      }

      // 設定で許可されたIPアドレス、または "0.0.0.0" (任意)
      // の場合のみ処理を続行
      if (client_host_val != "0.0.0.0" && client_host_val != client_ip_str) {
        // 警告ログのフラッド（あふれ）を防ぐため、正確に1秒間隔を空ける
        struct timeval now;
        gettimeofday(&now, NULL);

        double time_since_last =
            (double)(now.tv_sec - last_warning_time.tv_sec) +
            (double)(now.tv_usec - last_warning_time.tv_usec) / 1000000.0;

        if (time_since_last >= 1.0) {
          fprintf(stderr,
                  "警告: 許可されていないIPアドレス (%s) "
                  "からパケットを受信しました（以降の警告は省略）。\n",
                  client_ip_str);
          last_warning_time = now;
        }
        // このパケットは無視して次のパケットを読み取る
        continue;
      }

      // 有効なパケットとして記録 (上書き)
      final_recv_len = current_recv_len;
      valid_packet_received = true;

      // 送信先の更新処理 (最新のパケットのIP情報を使う)
      gettimeofday(&ctx->last_successful_recv_time, NULL); // 最終受信時刻を更新
      if (!ctx->client_addr_known ||
          ctx->client_addr_send.sin_addr.s_addr !=
              ctx->client_addr_recv.sin_addr.s_addr) {
        network_update_send_address(ctx);
      }
    } else if (current_recv_len < 0) {
      // EAGAIN/EWOULDBLOCK はデータがない(読み切った)ことを示すのでループ終了
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        break; // バッファ内のパケットをすべて処理した
      } else {
        // その他の致命的なエラー
        perror("受信エラー");
        if (!valid_packet_received)
          return -1; // これまで有効なパケットもなければエラーを返す
        break; // エラーだが、すでに有効なパケットを受け取っていればそれを返す
      }
    } else {
      // current_recv_len == 0 (UDPでは通常起こらないが、安全のため抜ける)
      break;
    }
  }

  // ループ終了後、有効なパケットを1つでも受信していれば、最後に書き込んだバッファを返す
  if (valid_packet_received) {
    buffer[final_recv_len] = '\0'; // Null終端
  }
  // 有効なパケットを受信していない、かつエラーでもない場合は 0 を返す
  else if (final_recv_len == -1) {
    final_recv_len = 0;
  }

  return final_recv_len;
}

// UDPデータを送信する関数
bool network_send(NetworkContext *ctx, const char *data, size_t data_len) {
  if (!ctx || ctx->send_socket < 0 || !data || !ctx->client_addr_known) {
    // 送信先が不明な場合は送信しない
    return false;
  }

  // データ送信試行
  ssize_t sent_len = sendto(ctx->send_socket, data, data_len, 0,
                            (const struct sockaddr *)&ctx->client_addr_send,
                            sizeof(ctx->client_addr_send));

  if (sent_len < 0) {
    // クライアント切断時などにログが溢れるのを避けるため、頻繁なエラー出力は避ける
    // perror("送信エラー");
    return false;
  } else if ((size_t)sent_len < data_len) {
    fprintf(stderr, "警告: データが部分的にしか送信されませんでした。\n");
    return false; // 部分送信もエラー扱いとするか、状況による
  }

  return true;
}

// 最後にデータを受信したクライアントのIPアドレスを送信先として設定/更新する関数
bool network_update_send_address(NetworkContext *ctx) {
  if (!ctx)
    return false;
  char client_ip_str[INET_ADDRSTRLEN];
  inet_ntop(AF_INET, &ctx->client_addr_recv.sin_addr, client_ip_str,
            INET_ADDRSTRLEN);
  printf("センサーデータ送信先を設定/更新: %s:%d\n", client_ip_str,
         ntohs(ctx->client_addr_send.sin_port)); // ポートは固定
  ctx->client_addr_send.sin_addr =
      ctx->client_addr_recv.sin_addr; // IPアドレスを更新
  ctx->client_addr_known = true;
  return true;
}
