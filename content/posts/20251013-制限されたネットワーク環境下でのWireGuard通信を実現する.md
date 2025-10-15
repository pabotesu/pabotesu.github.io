---
title: "20251013 制限されたネットワーク環境下でのWireGuard通信を実現する"
date: 2025-10-13T17:16:22+09:00
tags: ["wireguard","network"]
comments: true
showToc: true
---

## 概要

以前の記事「[WireGuardを利用したNATTraversalなP2P通信の実装](https://pabotesu.dev/posts/20250614-wireguard%E3%82%92%E5%88%A9%E7%94%A8%E3%81%97%E3%81%9Fnattraversal%E3%81%AAp2p%E9%80%9A%E4%BF%A1%E3%81%AE%E5%AE%9F%E8%A3%85/)」では、WireGuardを用いたP2P通信の仕組みを実装しました。  
しかし、この方式にはいくつかの制約がありました：

1. **Symmetric NATへの対応不足**: 現時点でSymmetric NAT環境での直接接続が困難
2. **UDP通信の必須要件**: 企業ネットワークや官公庁などでUDP通信が制限されている環境では利用不可

これらの課題を解決するフォールバック機能として、[hulegu](https://github.com/pabotesu/hulegu)というアプローチを実装しました。  
huleguは、制限されたネットワーク環境下でもWireGuard通信を実現するための仕組みです。

---

## Symmetric NAT環境でのWireGuard接続

### 問題の整理

Symmetric NAT環境では、P2P接続が困難になる理由として、以下の点が挙げられます：

- **ポートマッピングの動的変更**: 接続先が変わるたびにNATが新しいポートを割り当てる
- **外部からの直接接続の制限**: 事前に確立されていない接続は拒否される
- **UDPホールパンチングの困難性**: 従来のNATトラバーサル手法が通用しない

### 解決策：サーバ中継によるWireGuard接続

Symmetric NAT環境での最もシンプルで確実な解決策は、**WireGuardサーバを中継点として利用する**ことです。

```
[Peer A]   [Peer B]
    |         |
    |         |
    v         v
[WireGuard Server]
```

#### 仕組み

1. **各PeerがWireGuardサーバに接続**
   - Peer A、Peer BそれぞれがWireGuardサーバに対してVPN接続を確立
   - サーバ側では各Peerに仮想IPアドレスを割り当て

2. **サーバ経由での通信**
   - Peer AからPeer Bへの通信は、WireGuardサーバを経由してルーティング
   - 各Peerは直接接続する必要がなく、Symmetric NATの制約を回避

3. **設定の簡素化**
   - 従来のクライアント・サーバ型VPN設定と同様の構成
   - 複雑なNATトラバーサル処理は不要

### 実装例

#### サーバ側設定 (`/etc/wireguard/wg0.conf`)

```ini
[Interface]
PrivateKey = <サーバの秘密鍵>
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Peer A
[Peer]
PublicKey = <Peer Aの公開鍵>
AllowedIPs = 10.0.0.2/32

# Peer B
[Peer]
PublicKey = <Peer Bの公開鍵>
AllowedIPs = 10.0.0.3/32
```

#### Peer A設定

```ini
[Interface]
PrivateKey = <Peer Aの秘密鍵>
Address = 10.0.0.2/24

[Peer]
PublicKey = <サーバの公開鍵>
Endpoint = <サーバのパブリックIP>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

#### Peer B設定

```ini
[Interface]
PrivateKey = <Peer Bの秘密鍵>
Address = 10.0.0.3/24

[Peer]
PublicKey = <サーバの公開鍵>
Endpoint = <サーバのパブリックIP>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

### この方式の利点

- **確実性**: Symmetric NAT環境でも確実に接続が可能
- **シンプルさ**: 標準的なWireGuard設定のみで実現可能
- **管理性**: 従来のVPN管理手法をそのまま適用可能

### 制約事項

- **サーバリソース**: 全ての通信がサーバを経由するため、帯域幅とCPUリソースが必要
- **WireGuard通信の復号・再暗号化の必要性**: サーバ中継では、受信したWireGuardパケットを一度復号してから、転送先へ再度暗号化して送信する必要がある。
- **レイテンシ**: 直接接続と比較して通信遅延が発生
- **単一障害点**: サーバがダウンすると全体の通信が停止

---

## UDP制限・厳格なファイアウォール環境での対処

### 問題の整理

企業ネットワークや官公庁などの厳格なネットワーク環境では、以下の制限が課されることがあります：

- **UDP通信の全面禁止**: セキュリティポリシーによりUDPプロトコルが完全にブロック
- **特定ポートのみ許可**: HTTP(S)やSSHなど、限定されたポートのみが通信可能
- **プロトコル制限**: TCPのみ、または特定のアプリケーションプロトコルのみが許可

これらの環境では、WireGuardが標準で使用するUDP通信が利用できないため、別のアプローチが必要になります。

### 解決策：プロトコルカプセル化によるE2E接続

制限されたネットワーク環境での解決策として、**WireGuard通信を別のプロトコルでカプセル化**し、同様のプロトコルを理解するPeer同士でE2E接続を確立します。

```
[WS/TLS/HTTP]   ←→ [カプセル化] ←→ [ネットワーク] ←→ [カプセル化] ←→ [WS/TLS/HTTP]
   ↑                                                                 ↑
WireGuard                                                       WireGuard
   ↓                                                                 ↓
 [Peer A]                                                       [Peer B]
```

#### 対応プロトコル例

- **WebSocket over TLS**: HTTPS環境で利用可能
- **HTTP/HTTPS Tunneling**: プロキシ経由での通信
- **SSH Tunneling**: SSH接続が許可された環境での利用

#### 仕組み

1. **WireGuardパケットのカプセル化**
   - 送信側PeerがWireGuardパケットを指定プロトコル（例：WebSocket）でラップ
   - ファイアウォールからは許可されたプロトコルの通信として認識

2. **ネットワーク経由での転送**
   - カプセル化されたパケットが制限されたネットワークを通過
   - 中間機器では通常のWebトラフィック等として処理

3. **受信側での復元**
   - 受信側Peerがカプセル化を解除してWireGuardパケットを復元
   - 通常のWireGuard処理を継続

### この方式の利点

- **E2E暗号化の維持**: WireGuardの暗号化がそのまま保持される
- **環境適応性**: 様々な制限されたネットワーク環境に対応可能
- **透過性**: アプリケーションレイヤーからは通常のWireGuard接続として見える

### 制約事項

- **1対1接続の制限**: WireGuardの暗号化方式の都合により、特定のPeerとの1対1でしか利用できない
- **複数Peer接続時のコスト**: 複数PeerとのE2E接続を行うには、その都度カプセル化するプロトコルチャネルが必要
- **パフォーマンスオーバーヘッド**: カプセル化処理によるCPU負荷と帯域幅消費が発生


> **Note: WireGuardの暗号化特性と複数Peer通信の制約**
> 
> WireGuardは接続先Peerの公開鍵情報もPeerの公開鍵で暗号化して通信を行います。
> そのため、暗号化後の通信を他のプロトコルやプロキシで読み取ろうとしても、どのPeer宛の通信か判別できません。これが複数Peer間通信を困難にする根本的な要因です。
> 
> **既存サービでのアプローチ**  
> 市場に存在する既存サービスでは、この問題を解決するためにWireGuardをユーザランドで動作させ、実際の通信制御は通信用ソケットで行い、暗号化・復号化のみにWireGuardを利用しています。
> ただし、この方式ではカーネルモジュール版のWireGuardを利用できないため、パフォーマンス面でのトレードオフが発生します。
---

## 統合的アプローチについて

### 既存手法の課題と限界

これまで説明した2つの手法は、それぞれ特定の環境での課題を解決しますが、単独では以下の限界があります：

#### サーバ中継方式の限界
- **Symmetric NAT以外での非効率性**: 直接接続可能な環境でも常にサーバを経由
- **サーバの必要性**:サーバロールのPeerが必ず必要
- **スケーラビリティの問題**: 接続数増加に伴うサーバ負荷の線形増加

#### プロトコルカプセル化方式の限界
- **複数Peer接続の複雑性**: N対Nの接続でN²のカプセル化チャネルが必要

### WebRTCにおけるSTUN/TURNアーキテクチャ

ノード間の直接的通信を実現するための先行的な技術領域としてWebRTCが存在します。  
WebRTCでは、P2P接続が困難な環境に対する解決策として、段階的なフォールバック機構を採用しています。

```
接続試行の優先順位:

1. 直接接続 (Direct Connection)
   ↓ 失敗
2. STUN経由のP2P接続 (NAT Traversal)
   ↓ 失敗  
3. TURN経由の中継接続 (Relay Connection)
```

STUNによるNATトラバーサルを試行し、それでもP2P接続が確立できない場合（Symmetric NATや厳格なファイアウォール環境など）、**TURN** （Traversal Using Relays around NAT）のアプローチに切り替わります。

#### TURNアプローチの仕組み

TURNは、P2P接続が不可能な場合の代替え的な通信機構として機能します：

- **完全な中継機能**: 全ての通信データをTURNサーバが中継
- **透過的な動作**: TURNサーバはパケットを受け流す処理のみを実装、クライアントからは直接接続と同様に見える
- **接続保証**: 制限されたネットワーク環境でも接続を確立
- **接続の維持**: E2E接続の成功率を高いレベルで維持する

```
[Client A] ←→ [TURN Server] ←→ [Client B]
```

### WireGuardへのTURNアプローチの応用

また、今回はWebRTCのTURNアーキテクチャをWireGuard環境に応用可能ではないかという点に着目しました。  
TURNのアプローチに類似するものをWireGuard環境で再現し、前述の二つのアプローチの統合を行い、以下の機能の実現を目指します。

- **透過的な中継機能**: WireGuardパケットをそのまま中継し、クライアントからは通常のWireGuard接続として見える
- **プロトコルカプセル化対応**: UDP制限環境でも動作するよう、WebSocketやHTTPSなどでのカプセル化に対応
- **カーネルモジュール版でも利用可能な構成**: 可能な限りWireGuardの思想や接続方式を尊重し、あくまでWireGuardにおけるE2E接続のアタッチメントのような立ち位置の構成で作成する

これにより、WireGuard環境においてもWebRTCと同様な再現性の高いE2E接続を目指します。

---

## 筆者のアプローチ

### 概要

Huleguは、前述したWebRTCのTURNアプローチをWireGuard環境に応用した中継システムです。  
WireGuardの標準的な接続方式を可能な限り維持しながら、制限されたネットワーク環境でのE2E接続を実現します。

### アプローチ

Huleguは、WireGuardの接続を以下の構成で実現します：

#### WireGuardエンドポイントの提供とパケット中継
- **ローカルエンドポイントの提供**: HuleguProxyが各Peerに対してローカルのWireGuardエンドポイント（UDPソケット）を提供
- **WireGuard設定の再利用性**: 既存のWireGuard設定において、EndpointをHuleguProxyが提供するローカルアドレスに変更するだけで利用可能
- **プロトコル変換**: HuleguProxyが受信したWireGuardパケットをWebSocketでカプセル化
- **透過的な転送**: 中継サーバを経由してパケットを対向Peerに転送
- **元のWireGuard処理の継続**: 受信側で元のUDPパケットに復元し、WireGuardに渡す
- **公開鍵ベースの経路選択**: WebSocketでカプセル化に含まれる公開鍵情報を元に適切な転送先を決定

この方式により、WireGuard自体は通常のE2E通信と同様に動作し、暗号化・復号化も従来通り各Peer間で実行されます。

### 設定例

#### 従来のWireGuard設定
```ini
[Interface]
PrivateKey = <Peer Aの秘密鍵>
Address = 10.0.0.2/24

[Peer]
PublicKey = <Peer Bの公開鍵>
Endpoint = <Peer BのパブリックIP>:51820  # 直接接続
AllowedIPs = 10.0.0.3/32
```

#### hulegu使用時のWireGuard設定
```ini
[Interface]
PrivateKey = <Peer Aの秘密鍵>
Address = 10.0.0.2/24

[Peer]
PublicKey = <Peer Bの公開鍵>
Endpoint = 127.0.0.1:51821  # HuleguProxyが提供するローカルエンドポイント
AllowedIPs = 10.0.0.3/32
```

WireGuardからの視点では、単にローカルの別ポートに接続しているだけのように見え、実際の中継処理はHuleguProxyが担当します。



### Hulegu接続のアーキテクチャ図
![hulegu-arch](/img/20251015-hulegu/hulegu-arch_white.png)


### データフローの詳細

```
1. WireGuardパケットの送信
   [Peer A WireGuard] → UDP:127.0.0.1:xxxxx → [HuleguProxy A]

2. パケットの解析とカプセル化
   [HuleguProxy A] → 公開鍵取得 → WebSocketメッセージ化

3. サーバ経由の転送
   [HuleguProxy A] → WSS → [hulegu-server] → WSS → [HuleguProxy B]

4. パケットの復元と配信
   [HuleguProxy B] → UDPパケット復元 → UDP:51821 → [Peer B WireGuard]
```

## 検証

### サーバ実行
```
root@vultr:~/hulegu# ./hulegu-server start --addr=:8080 --path=/ws
Starting Hulegu server on :8080/ws
Log level: info
TLS disabled
All peers allowed
2025/10/15 12:51:57 Starting HTTP server on :8080
```
### クライアント側の実行
クライアント側実行前
```
interface: wg0
  public key: mMeSJSBdLnowAdxaU4kn4pN6+vYcMw3lwEbwusG2cx8=
  private key: (hidden)
  listening port: 40402

peer: /sS4x1w8/Kn49o33xOQSSaX5+SEkojsjZEJEhtpFpEU=
  allowed ips: 100.100.0.24/32

peer: Qaa1DPasTqt+EBwDFMrzPO71pIdw1OSMVTIeABhdFUY=
  allowed ips: 100.100.0.25/32
```
クライアント実行後、endpointが更新される
```
root@vultr:~/hulegu# nohup ./hulegu-client start --server=ws://198.xxx.xxx.xxx:8080/ws --interface=wg0 --enable-peer=/sS4x1w8/Kn49o33xOQSSaX5+SEkojsjZEJEhtpFpEU= --enable-peer=Qaa1DPasTqt+EBwDFMrzPO71pIdw1OSMVTIeABhdFUY= > client_osaka.log 2>&1 &
[1] 10414
root@vultr:~/hulegu# wg
interface: wg0
  public key: mMeSJSBdLnowAdxaU4kn4pN6+vYcMw3lwEbwusG2cx8=
  private key: (hidden)
  listening port: 40402

peer: /sS4x1w8/Kn49o33xOQSSaX5+SEkojsjZEJEhtpFpEU=
  endpoint: 127.0.0.1:52453
  allowed ips: 100.100.0.24/32

peer: Qaa1DPasTqt+EBwDFMrzPO71pIdw1OSMVTIeABhdFUY=
  endpoint: 127.0.0.1:60693
  allowed ips: 100.100.0.25/32
root@vultr:~/hulegu#
```
サーバ側で接続を確認
```
2025/10/15 12:52:23 Client mMeSJSBdLnowAdxaU4kn4pN6+vYcMw3lwEbwusG2cx8= authenticated with session 0586db7084921ead5c064f88e08fa452
```

ping実行
```
root@vultr:~/hulegu# ping -c2 100.100.0.24                                                                                                                                        PING 100.100.0.24 (100.100.0.24) 56(84) bytes of data.
64 bytes from 100.100.0.24: icmp_seq=1 ttl=64 time=32.0 ms
64 bytes from 100.100.0.24: icmp_seq=2 ttl=64 time=15.6 ms

--- 100.100.0.24 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 15.607/23.806/32.005/8.199 ms
root@vultr:~/hulegu# ping -c2 100.100.0.25                                                                                                                                        PING 100.100.0.25 (100.100.0.25) 56(84) bytes of data.
64 bytes from 100.100.0.25: icmp_seq=1 ttl=64 time=32.8 ms
64 bytes from 100.100.0.25: icmp_seq=2 ttl=64 time=13.9 ms

--- 100.100.0.25 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 13.895/23.368/32.842/9.473 ms
root@vultr:~/hulegu#
```

### `/sS4x1w8/Kn49o33xOQSSaX5+SEkojsjZEJEhtpFpEU=`(100.100.0.24)受信側の通信証左

WireGuardインターフェースでも受信を確認
```
root@hulegu-clinet-verification01:~/hulegu# tcpdump -i wg0 -v
tcpdump: listening on wg0, link-type RAW (Raw IP), snapshot length 262144 bytes
21:58:29.213195 IP (tos 0x0, ttl 64, id 63938, offset 0, flags [DF], proto ICMP (1), length 84)
    100.100.0.23 > 100.100.0.24: ICMP echo request, id 7, seq 1, length 64
21:58:29.213216 IP (tos 0x0, ttl 64, id 40187, offset 0, flags [none], proto ICMP (1), length 84)
    100.100.0.24 > 100.100.0.23: ICMP echo reply, id 7, seq 1, length 64
21:58:30.212466 IP (tos 0x0, ttl 64, id 64717, offset 0, flags [DF], proto ICMP (1), length 84)
    100.100.0.23 > 100.100.0.24: ICMP echo request, id 7, seq 2, length 64
21:58:30.212493 IP (tos 0x0, ttl 64, id 41002, offset 0, flags [none], proto ICMP (1), length 84)
    100.100.0.24 > 100.100.0.23: ICMP echo reply, id 7, seq 2, length 64
^C
4 packets captured
4 packets received by filter
0 packets dropped by kernel
root@hulegu-clinet-verification01:~/hulegu#
```
物理インターフェース側、websocketでの通信を確認
```
root@hulegu-client-verification01:~/hulegu# tcpdump -i eth0 -n 'port 8080'
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
22:01:40.080364 IP XXX.XXX.XXX.XXX.8080 > 192.168.139.168.33842: Flags [P.], seq 1596060584:1596060789, ack 620488031, win 4096, options [nop,nop,TS val 1841712726 ecr 754588659], length 205: HTTP
22:01:40.080770 IP 192.168.139.168.33842 > XXX.XXX.XXX.XXX.8080: Flags [P.], seq 1:22, ack 205, win 63, options [nop,nop,TS val 754641682 ecr 1841712726], length 21: HTTP
22:01:40.080908 IP XXX.XXX.XXX.XXX.8080 > 192.168.139.168.33842: Flags [.], ack 22, win 4095, options [nop,nop,TS val 1841712726 ecr 754641682], length 0
22:01:40.082321 IP 192.168.139.168.33842 > XXX.XXX.XXX.XXX.8080: Flags [P.], seq 22:231, ack 205, win 63, options [nop,nop,TS val 754641684 ecr 1841712726], length 209: HTTP
22:01:40.082467 IP XXX.XXX.XXX.XXX.8080 > 192.168.139.168.33842: Flags [.], ack 231, win 4094, options [nop,nop,TS val 1841712728 ecr 754641684], length 0
22:01:40.084186 IP XXX.XXX.XXX.XXX.8080 > 192.168.139.168.33842: Flags [P.], seq 205:247, ack 231, win 4096, options [nop,nop,TS val 1841712729 ecr 754641684], length 42: HTTP
22:01:40.124985 IP 192.168.139.168.33842 > XXX.XXX.XXX.XXX.8080: Flags [.], ack 247, win 63, options [nop,nop,TS val 754641727 ecr 1841712729], length 0
22:01:41.080816 IP XXX.XXX.XXX.XXX.8080 > 192.168.139.168.33842: Flags [P.], seq 247:452, ack 452, win 4096, options [nop,nop,TS val 1841713726 ecr 754641727], length 205: HTTP
22:01:41.080865 IP 192.168.139.168.33842 > XXX.XXX.XXX.XXX.8080: Flags [.], ack 452, win 63, options [nop,nop,TS val 754642682 ecr 1841713726], length 0
22:01:41.082774 IP 192.168.139.168.33842 > XXX.XXX.XXX.XXX.8080: Flags [P.], seq 231:440, ack 452, win 63, options [nop,nop,TS val 754642684 ecr 1841713726], length 209: HTTP
22:01:41.082942 IP XXX.XXX.XXX.XXX.8080 > 192.168.139.168.33842: Flags [.], ack 440, win 4094, options [nop,nop,TS val 1841713728 ecr 754642684], length 0
```
endpointで行われる通信を確認
```
root@hulegu-clinet-verification01:~/hulegu# tcpdump -i lo -n 'port 49777'
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on lo, link-type EN10MB (Ethernet), snapshot length 262144 bytes
22:04:54.762145 IP 127.0.0.1.49777 > 127.0.0.1.59631: UDP, length 148
22:04:54.762951 IP 127.0.0.1.59631 > 127.0.0.1.49777: UDP, length 92
22:04:54.780038 IP 127.0.0.1.49777 > 127.0.0.1.59631: UDP, length 128
22:04:54.780188 IP 127.0.0.1.59631 > 127.0.0.1.49777: UDP, length 128
22:04:55.772664 IP 127.0.0.1.49777 > 127.0.0.1.59631: UDP, length 128
22:04:55.772836 IP 127.0.0.1.59631 > 127.0.0.1.49777: UDP, length 128
```

---

## まとめ

本記事では、制限されたネットワーク環境下でのWireGuard通信を実現するための取り組みについて解説しました。


### 解決した課題

前回の記事で挙げた制約に対して、huleguの実装により具体的な解決策を提示することができました。

まず、Symmetric NAT環境での接続困難という課題については、パケットを復号化せずに中継する機能で通信を実現できました。 
WireGuardの設定をほぼそのまま活用しながら、公開鍵ベースの経路選択により効率的なパケット転送を可能にします。  
これにより、クライアント側はアウトバウンドの通信のみで成立するため、確実な接続を確立できるようになりました。
また、huleguでは、WireGuardパケットをWebSocketでカプセル化することで、企業ネットワークや官公庁などの厳格なファイアウォール環境でも通信を可能にしています。  
加えて、この実装ではカーネルモジュール版WireGuardをそのまま利用できる利点もあります。

### 今後の展望

現在の実装は基礎的な中継機能を提供していますが、以下の拡張を検討しています：

- **自動フォールバック機能**: 直接接続失敗時の自動的な中継モード切り替え
- **負荷分散機能**: 複数の中継サーバによる冗長化と負荷分散
- **中継サーバ同士の通信** : 中継サーバを複数設け、サーバ間で通信を行い、より広域なネットワークを確保

## 参考
- https://tailscale.com/kb/1232/derp-servers
- https://gist.github.com/voluntas/a1d39c2b2a4392956ff69732dc493e39
- https://www.youtube.com/watch?v=grDEBt7oQho
- https://github.com/jnsgruk/wireguard-over-wss
- https://github.com/coturn/coturn
- 徹底解説 v6プラス(https://www.amazon.co.jp/%E5%BE%B9%E5%BA%95%E8%A7%A3%E8%AA%AC-v6%E3%83%97%E3%83%A9%E3%82%B9-%E5%B0%8F%E5%B7%9D%E6%99%83%E9%80%9A/dp/4908686084)
- https://docs.netbird.io/about-netbird/how-netbird-works
