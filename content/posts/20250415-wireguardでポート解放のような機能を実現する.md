---
title: "20250415 Wireguardでポート開放のような機能を実現する"
date: 2025-04-15T23:31:20+09:00
tags: ["wireguard","network"]
comments: true
showToc: true
---

# Wireguardでポート開放のような機能を実現する

## 注意点
本稿で実装した機能については限定的な用途に絞っており、\
読者の皆様のネットワーク環境における安全性を確実に担保する保障はございません。\
試用される際は自己責任でお願いします。\
あと、普通に悪用厳禁です。

## はじまり
私事ではありますが、引越しを経て大きくネットワーク環境を変更するに至りました。\
詳しい言及は本稿では避けますが、一般的なIPv6環境(MAP-Eによる広告)と相成りました。\
お察しの通り、この状態だとポート開放はいささか難しいものがございます。\
特に最近の傾向ですと己がサービスをISPの網を通して公開するというのは避けがちとの所感を得ております。\
そこで、[wiregurad](https://www.wireguard.com/)を利用して擬似ポート開放のような物を実現できないかと思慮した次第でございます。

## 実現可能なサービスについて
当方の思慮している環境を構築できる既存サービスはいくつかあります。
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [ngrock](https://ngrok.com/)
- [Tailscale](https://tailscale.com/)
- etc ...

今を馳せるクラウドネットワークリソースサービスの皆様ですね

## 実装例
![wireguard_open_ports.png](/img/20250416-wireguard-openport/wireguard_open_ports.png)

### 解説
1. user01はvpsに付与されているglobalIPアドレス宛に8080ポートにアクセス
2. vpsで動作するwireguardは事前に設定されているポートとIPアドレス宛にポート転送を行う
3. 自宅で動作しているwebサーバはwireguardの網を通してHTMLコンテンツをuser01に表示する

ザックリ上記の動作を実装しました

## 詳細

### vps側の設定例
vps側のIP状態
```
root@vultr:~# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: enp1s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 56:00:05:40:cc:a0 brd ff:ff:ff:ff:ff:ff
    inet 198.xxx.xxx.xxx/23 metric 100 brd 198.13.53.255 scope global dynamic enp1s0
       valid_lft 85682sec preferred_lft 85682sec
    <snip>
6: wg80: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none
    inet 10.0.0.1/24 scope global wg80
       valid_lft forever preferred_lft forever
```
vps側のwiregusard設定
```
root@vultr:~# cat /etc/wireguard/wg80.conf
[Interface]
# サーバーのプライベートキー
PrivateKey = <snip>
# サーバーのVPN内IPアドレス
Address = 10.0.0.1/24
# サーバーがリッスンするポート
ListenPort = 51820

# トンネル接続時に実行するコマンド（例：NATルールの追加）
PostUp = nft add table ip nat; nft add chain ip nat prerouting { type nat hook prerouting priority 0 \; }; nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }; nft add rule ip nat prerouting tcp dport 8080 dnat to 10.0.0.2:8080; nft add rule ip nat postrouting oif enp1s0 masquerade

# トンネル切断時に実行するコマンド（例：NATルールの削除）
PostDown = nft delete table ip nat

[Peer]
# クライアントの公開鍵
PublicKey = snip
# クライアントのVPN内IPアドレス
AllowedIPs = 10.0.0.2/32

root@vultr:~#
```
上記の設定で外部から受けた8080の通信に限り、peerに転送するようにしてます。


### クライアント（webサーバ側）の設定
クライアント（webサーバ側）のIP状態
```
root@pabotesu-raspi:/home/pabotesu# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether e4:5f:01:10:d0:ad brd ff:ff:ff:ff:ff:ff
    inet 192.168.100.57/24 brd 192.168.100.255 scope global noprefixroute eth0
       valid_lft forever preferred_lft forever
    <snip>
3: wlan0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether e4:5f:01:10:d0:ae brd ff:ff:ff:ff:ff:ff
5: wg80: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none
    inet 10.0.0.2/2 scope global wg80
       valid_lft forever preferred_lft forever
root@pabotesu-raspi:/home/pabotesu#
```
snipしてますが、ここでIPv6が振られてます。\
通常インターネットに出る際はIPv6を利用し、IPv4サイトへはトンネルングされてアクセスします。

クライアント（webサーバ側）のwireguardの設定
```
root@pabotesu-raspi:/home/pabotesu# cat /etc/wireguard/wg80.conf
[Interface]
#client privatekey
PrivateKey = <snip>
Address = 10.0.0.2/2

[Peer]
#server publickey
PublicKey = <snip>
Endpoint = 198.xxx.xxx.xxx:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
root@pabotesu-raspi:/home/pabotesu#
```
普通にvpsに接続されます。\
`PersistentKeepalive`の設定を入れることにより、接続性を維持できます。\
外から受ける8080のアクセスはあくまで、wireguardの通信外での動きなので、このようにセッションを維持する設定が必要です。

あとは適当にwebサーバで8080を受けるようにしてやれば、準備完了
```
root@pabotesu-raspi:/home/pabotesu# cat /etc/nginx/sites-available/default
<snip>
#
server {
        listen 8080 default_server;
        listen [::]:8080 default_server;
```

### アクセステスト
以下のようにvpsのglobalIPに8080でアクセスすれば自宅のwebサーバで回しているコンテンにアクセスできました。

![wireguad_webpage.png](/img/20250416-wireguard-openport/wireguad_webpage.png)

以上となります。

## 展望
- 近いうちにglobalIPを持っているサーバ側の設定を簡易的にできるツールを作ります。
- 次のモチベーション的にクライアント間通信を実現して、tailscaleっぽい通信動作を作ってみようと思います。
    - この場合特定通信に絞って疎通させるので、クライアント側にルーティング設定が必要そうです。
- 更に先には現在nftablesで実装している部分をnetlinkで実装して、いろんなディストロで使えるようにしてみたり、ネットワークの低レイヤを理解できるようにします。

## 参考
- https://www.wireguard.com/#conceptual-overview
- https://www.wireguard.com/#cryptokey-routing
- https://manual.iij.jp/iot/doc/47981302.html
