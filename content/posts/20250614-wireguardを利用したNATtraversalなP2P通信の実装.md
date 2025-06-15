---
title: "20250614 Wireguardを利用したNATtraversalなP2P通信の実装"
date: 2025-06-14T22:27:49+09:00
tags: ["wireguard","p2p","network"]
comments: true
showToc: true
---

# Wireguardを利用したNATtraversalなP2P通信の実装

## はじめに
インターネット越しにセキュアかつ柔軟に通信を行う手段として、WireGuard をベースにした VPN やメッシュネットワークの仕組みが注目されています。
近年では Tailscale や ZeroTier といった製品が登場し、NAT越えやピア同士の自動接続といった課題を見事に解決しています。

本記事では、WireGuard + etcdによる簡易的なP2Pメッシュネットワーク構築の実装例として、筆者が提案する「kurohabaki」というアプローチについて紹介します。

「kurohabaki」は、以下のような要件を満たすシンプルな仕組みを目指して開発されました
- WireGuardを使って各ノードが相互に接続される
- etcdを使ってノード情報（公開鍵、IP、endpointなど）を一元管理
- STUN(に類似するアプローチ)を用いてNAT越しのendpoint情報を自動検出・更新
- Server側でPeer情報を統合し、全ノードが疎通可能な構成を維持

これらをGo言語で実装し、Linux上で動作するクライアント・サーバ構成を実験的に作りました。
最初は個人的なネットワーク実験環境の構築が目的でしたが、想像以上に柔軟性があり、また市販サービスの仕組みを理解する良い教材にもなりました。

## 業界の動向と周辺技術
### 現行VPNのネットワーク構成
![現行のVPN](/img/20250614-kurohabaki-p2p/current_vpn.png)

現在主流のVPN構成は、ハブアンドスポーク型ネットワーク構成が一般的です。
この構成では、VPNサーバが通信のハブとして機能し、各ノード（クライアント）はスポークとしてサーバ経由で他ノードと通信します。

拠点間VPNのように、専用のVPN装置同士を接続する構成も存在しますが、ノード単位での接続、つまりエンドユーザ端末やサービスごとの細かな接続を行いたい場合も、基本的にはVPNサーバ（ハブ）を介した接続になります。

現行のVPNの構成だと、以下の課題も存在します。

- 単一障害点（SPOF）：中央のVPNサーバが停止すると、全ノード間の通信が断絶する
- スケーラビリティの限界：ノード数が増えると、サーバ側の負荷（CPU, メモリ, 帯域）が急増し、性能劣化や接続制限が発生しやすい
- レイテンシの増加：ノード間通信が常にハブを経由するため、物理的に近いノード同士でも遠回りのルートになることがある
- 構成が固定的：クライアントは基本的にサーバを介する前提で設計されており、柔軟なピア間通信や動的構成変更が難しい

上記の課題を解決するために、以下のような新たなVPNの構成に注目が集まっております。

### メッシュ型VPNの登場と再定義されるネットワーク構成

![メッシュ型VPN](/img/20250614-kurohabaki-p2p/nextgen_vpn.png)

今までのハブアンドスポーク型のネットワーク構成から、メッシュ型のネットワーク構成を利用するVPNサービスが台頭しております。

メッシュ型の構成では、各ノードが等しくネットワークに参加し、必要に応じて他ノードと直接接続して通信を行います。つまり、ノード同士がP2Pで接続し、中央のサーバを中継することなく最短経路での通信が可能になります。

この構成の最大の特徴は、中央の通信ハブを必要としないことです。もちろん、ノード情報の登録やキー交換といったコントロールプレーンは必要になりますが、実際のデータ通信はノード間で完結するため、トラフィックの集中を避けることができ、構成全体がよりシンプルかつ柔軟になります。

同ネットワーク構成には特に以下のような有性があります。

- スケーラビリティに優れる：ノード数が増えてもトラフィックが一箇所に集中しないため、全体のパフォーマンスが劣化しにくい。
- 自律分散的な構成が可能：一部のノードやサーバがダウンしても、他ノード間の通信は継続できる（フォールトトレラント性の向上）。
- 拠点・端末間通信の最適化：地理的・論理的に近いノード同士が直接接続されることで、VPN経由の遅延や帯域使用が最小化される。
- 柔軟な拠点構成：拠点ごとにVPN装置を用意する必要がなく、ソフトウェアだけで動的に接続を構成できる。

### メッシュ型VPNが抱える課題

メッシュ型VPNは、ノード間の直接通信を基本とすることで、レイテンシの低減やトラフィックの分散といった多くのメリットをもたらします。しかしその一方で、すべてのノードがP2Pで接続できることを前提としているため、ネットワーク越え（NAT越え）やファイアウォール通過といった技術的課題に直面します。

#### NAT越え（NAT Traversal）の必要性

多くのノードは家庭用ルータやクラウド環境の背後で動作しており、プライベートIPアドレスを持つ「NATデバイスの配下」に存在します。この場合、外部からそのノードへ直接アクセスすることができず、P2P通信が成立しないという問題が発生します。

接続のためには、相手ノードのグローバルIPアドレスとポート番号（NAT変換後の情報）を取得する必要があり、NAT(本稿では主にIPマスカレード,NAPTを想定)の動的なIP:Portのマッピングに対応する必要があります。

しかし、すべてのNATがこのような仕組みに対応できるわけではなく、Symmetric NAT や キャリアグレードNAT（CGN） のように、外部との直接通信が難しいケースも少なくありません。


#### ステートフルファイアウォールの存在
さらに問題を複雑にするのが、ステートフル（状態保持型）ファイアウォールの存在です。
この種のファイアウォールは、**「内から外への通信に対してのみ応答パケットを許可する」** というポリシーで設計されていることが多く、外部からのP2P通信要求は通常ブロックされます。

たとえNAT越えに必要なグローバル(NAT変換後)IP:Portが判明しても、ファイアウォールが初動の通信を遮断してしまうと、P2P接続そのものが成立しない可能性があります。

## P2P接続を支える技術
メッシュ型VPNにおけるノード間通信は、基本的にSTUNとUDP Hole Punchingを活用して成立します。

各ノードは起動時または定期的に、STUNサーバに対してリクエストを送信し、自分のグローバルIPアドレスとNAT変換後のポート番号を取得します。この情報は、そのノードがNAT越しに外部と通信するための「名刺」として機能し、シグナリングサーバに登録されます。

次に、別のノードがこの情報を取得し、そのアドレス・ポートに対してUDPパケットを送信することでP2P接続を試みます。相手側も同様にパケットを送ることで、両者のNATテーブルが書き換わり、「UDPの通れる穴（Hole）」が一時的に開くことになります。これが UDP Hole Punching です。

この通信経路が確立されると、UDPなどの通信レイヤがP2P上に展開され、通信が可能になります。さらに、Keepalive パケットを定期的に送ることで、NATによるセッションの期限切れを防ぎ、通信状態を維持し続けることができます。

もし、これらの方法でP2P接続が確立できない場合には、シグナリングや中継を行うためのTURNサーバ的な機構を導入することで通信を補完するアプローチもあります。

このように、メッシュVPNのP2P接続は単に「IPアドレスを知っている」だけでは成立せず、NATやファイアウォールを巧みにすり抜ける複数の技術が裏で連携することで初めて成り立っています。

上記のようなP2P接続を支える技術はWebRTCなどのリアルタイム通信に必要とされ発展してきた経緯もあります。
- STUN (Session Traversal Utilities for NAT)：自身のグローバルIPアドレスおよびNAT変換後のポート番号を知るための仕組み。
- UDP Hole Punching：NATを動的に“開通”させる技術。双方から同時にUDPパケットを送り合うことで、ステートフルファイアウォールが通信を許可する状態を作る。
- シグナリングサーバ（Signaling Server）：グローバルアドレス・ポートなどの接続情報などを一時的に仲介・共有する中継点。
- Failover Fallback（TURN的な構造）：P2P通信が確立できなかった場合に備え、中継サーバを経由した通信に自動的に切り替える仕組み。

動作イメージ
```
1. [Node A] STUNサーバに問い合わせ → 自身の外部IP:Portを取得
2. [Node A] Signaling Serverに自身の外部IP:Port等の接続情報を登録
3. [Node B] 同様にSTUNに問い合わせ、Signaling Serverに登録を実施
4. [Node A] Signaling ServerからNode Bの接続情報を取得
5. [Node B] Signaling ServerからNode Aの接続情報を取得
6. [Node A & B] 互いにUDPパケットを同時送信（UDP Hole Punching）
7. [両者] NATが開通すればにUDP接続を開始
```
![UDP holepunching](/img/20250614-kurohabaki-p2p/udpholepunching.drawio.png)

## 筆者のアプローチ - kurohabaki

### 解説
筆者のアプローチについて解説します。

kurohabakiの最大の特徴は、専用のSTUN/TURNサーバを必要とせず、WireGuard 接続そのものを通じて NAT 越しの通信情報（endpoint）を把握し、サーバが自動で etcd に登録する構成にあります。これにより、ネットワーク構成を複雑にすることなく、NAT配下のノード同士でも直接通信が可能になります。

クライアントは、サーバと WireGuard 接続を確立したのち、etcd から他ノードの接続情報を取得し、WireGuard ピアを動的に構成します。サーバ側もすべてのノードの情報を保持し、WireGuard のインターフェースと peers を通じて中心的な役割を担いますが、通信経路そのものは P2P で最適化されます。


- https://github.com/pabotesu/kurohabaki-client
- https://github.com/pabotesu/kurohabaki-server

動作イメージ
```
1.	クライアントが起動し、自身の設定と鍵情報を読み込む
2.	WireGuardインターフェースを作成し、サーバと接続を確立する
3.	サーバ側でもWireGuardが動作しており、クライアントからの接続を受け入れる
4.	サーバはWireGuard経由で接続してきたクライアントのIP:Port（＝endpoint）を把握し、etcdに登録する
5.	クライアントはetcdから他ノードの接続情報（public_key, ipアドレス, endpointなど）を取得する
6.	取得した情報をもとにWireGuardピアを構成し、他ノードと直接接続を試みる
7.	複数ノード間で直接通信が成立し、メッシュ型VPNネットワークが形成される
```

![kurohabaki](/img/20250614-kurohabaki-p2p/kurohabaki.drawio.png)

### 動作の確認

#### サーバ側の起動
- サーバが起動したら、configを読み取り、自身の公開鍵情報・IPの情報を登録し、インターフェースを起動します。
- インターフェースが起動した際にはwireguard接続後のroute情報をOSに設定します。
- インターフェースの起動に成功すると、etcdを起動し、自らが接続します。
```
root@vultr:~/kurohabaki-server# ./kh-server-linux run --config ./config.yaml
Using config file: ./config.yaml
2025/06/15 04:48:43 kurohabaki-server starting...
2025/06/15 04:48:43 Server will listen on 198.xxx.xxx.xxx:5yyyyy
2025/06/15 04:48:43 WireGuard interface IP: 100.100.96.1
2025/06/15 04:48:43 Allocated subnet range: 100.100.96.0/24
2025/06/15 04:48:43 WireGuard interface 'kh0' configured
2025/06/15 04:48:43 etcd endpoint: localhost:2379
2025/06/15 04:48:43 Registered self (XsLrrIyasNoSa6ypyOkVscSzsZaOWYAu3nRyKhr3g0U=) with IP 100.100.96.1 in etcd
2025/06/15 04:48:43 Started peer endpoint observation loop
```

#### nodeの登録
- nodeの追加にはnodeの公開鍵情報が必要となります。
- 公開鍵情報を受け取るとetcdに接続情報を追加して、node側の設定に必要な情報を出力します。
- この際、wireguardのPeer情報も更新します。
```
root@vultr:~/kurohabaki-server# ./kh-server-linux node add "0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg="
Using config file:

# Client YAML configuration
interface:
    private_key: <YOUR_PRIVATE_KEY_HERE>
    address: 100.100.96.2/32
    dns: 100.100.96.1
    routes:
        - 100.100.96.0/24
peer:
    public_key: XsLrrIyasNoSa6ypyOkVscSzsZaOWYAu3nRyKhr3g0U=
    endpoint: 198.xxx.xxx.xxx:5yyyyy
    allowed_ips: 100.100.96.1/32
    persistent_keepalive: 5
etcd:
    endpoint: 100.100.96.1:2379

2025/06/15 04:53:00 Added peer 0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg= with IP 100.100.96.2 to WireGuard
```
```
interface: kh0
  public key: XsLrrIyasNoSa6ypyOkVscSzsZaOWYAu3nRyKhr3g0U=
  private key: (hidden)
  listening port: 51820

peer: 0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=
  allowed ips: 100.100.96.2/32
root@vultr:~/kurohabaki-server#
```
```
root@vultr:~/kurohabaki-server# etcdctl get /kurohabaki/nodes --prefix                 /kurohabaki/nodes/0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=/endpoint

/kurohabaki/nodes/0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=/ip
100.100.96.2
/kurohabaki/nodes/0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=/last_seen
2025-06-15T04:53:00Z
/kurohabaki/nodes/XsLrrIyasNoSa6ypyOkVscSzsZaOWYAu3nRyKhr3g0U=/ip
100.100.96.1
/kurohabaki/nodes/XsLrrIyasNoSa6ypyOkVscSzsZaOWYAu3nRyKhr3g0U=/last_seen
2025-06-15T04:48:43Z
root@vultr:~/kurohabaki-server#
```
#### クライアント側の動作
- クライアントはサーバから受け取った設定をもとに起動します。
- 起動のタイミングでwireguardの接続を行うインターフェースを起動し、OSにroute情報を設定します。
- 起動したクライアントはサーバにwireguardでの接続を試みます。
- サーバに対するwireguard接続に成功するとクライアント側でhttpのリクエストを叩き、etcdから自分以外の接続情報の取集を行います。
```
pabotesu@kh-client:~/kurohabaki-client$ sudo ./kh-client-linux up --config ./config.yam
2025/06/15 13:58:46 kurohabaki client starting...
2025/06/15 13:58:46 Bringing up WireGuard interface...
2025/06/15 13:58:46 Created TUN device: kh0
<snip>
2025/06/15 13:58:46 Adding route to 100.100.96.0/24 via kh0
2025/06/15 13:58:46 WireGuard interface is up
2025/06/15 13:58:46 🔑 selfPubKey: 0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=
2025/06/15 13:58:46 🔎 Peer count in conf: 1
2025/06/15 13:58:46 ✅ Peers in config: 1
2025/06/15 13:58:46 ✅ PublicKey (self): 0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=
2025/06/15 13:58:46 ✅ etcd endpoint: 100.100.96.1:2379
2025/06/15 13:58:46 ✅ Starting Agent...
2025/06/15 13:58:46 🟢 Agent.Run started
2025/06/15 13:58:46 🟢 Launching StartPeerWatcher goroutine
2025/06/15 13:58:46 🟡 StartPeerWatcher: launched
DEBUG: [WG-kh0] 2025/06/15 13:58:46 peer(XsLr…3g0U) - Received handshake response
DEBUG: [WG-kh0] 2025/06/15 13:58:51 peer(XsLr…3g0U) - Sending keepalive packet
<snip>
DEBUG: [WG-kh0] 2025/06/15 13:58:46 peer(XsLr…3g0U) - Received handshake response
DEBUG: [WG-kh0] 2025/06/15 13:58:51 peer(XsLr…3g0U) - Sending keepalive packet
2025/06/15 13:58:56 🔵 FetchPeers: start fetching from etcd...
2025/06/15 13:58:56 🚫 Skipping self pubKey: 0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=
2025/06/15 13:58:56 🚫 Skipping self pubKey: 0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=
2025/06/15 13:58:56 🚫 Skipping self pubKey: 0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg=
2025/06/15 13:58:56 🟢 FetchPeers: 0 node(s) fetched
2025/06/15 13:58:56 📶 Peers converted: 0
2025/06/15 13:58:56 ✔ No peer changes detected
```
```
pabotesu@kh-client:~$ ip a show dev kh0
99: kh0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1420 qdisc fq_codel state UNKNOWN group default qlen 500
    link/none
    inet 100.100.96.2/32 scope global kh0
       valid_lft forever preferred_lft forever
    inet6 fe80::df47:ae6f:e76f:824c/64 scope link stable-privacy proto kernel_ll
       valid_lft forever preferred_lft forever
pabotesu@kh-client:~$
```

#### Node間接続
- etcdの周期的な探索のうち、新たなNodeの情報・Node情報の変更を検知すると更新された内容を取得します。
- 取得した内容から変更された情報に沿って、Peer情報(AllowedIPsの情報も含む)を更新・追加します。
- Peer情報の更新に成功すると、wireguardの自動接続する習性を利用して、wireguardでの接続を試みます。
```
2025/06/15 14:07:26 🟢 FetchPeers: 1 node(s) fetched
2025/06/15 14:07:26 🧩 Node: {PublicKey:TfIcQ2IvIYbBUr5k5pw12Fsj5CGXRA558nRTLeXRllo= IP:100.100.96.3 Endpoint:49.xxx.xxx.xxx:6xxxx LastSeen:2025-06-15 05:07:28 +0000 UTC}
2025/06/15 14:07:26 📶 Peers converted: 1
2025/06/15 14:07:26 ⚠ Peer list updated, applying to interface...
2025/06/15 14:07:26 📌 AllowedIP: 100.100.96.3/32
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - UAPI: Created
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - UAPI: Updating endpoint
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - UAPI: Updating persistent keepalive interval
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - UAPI: Removing all allowedips
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - UAPI: Adding allowedip
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - Starting
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - Sending keepalive packet
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - Sending handshake initiation
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - Routine: sequential sender - started
DEBUG: [WG-kh0] 2025/06/15 14:07:26 peer(TfIc…Rllo) - Routine: sequential receiver - started
2025/06/15 14:07:26 ✅ Peers updated successfully
DEBUG: [WG-kh0] 2025/06/15 14:07:31 peer(TfIc…Rllo) - Sending handshake initia
```

接続に成功すると、wireguardのkeepalive packetを送信します
```
DEBUG: [WG-kh0] 2025/06/15 14:29:26 peer(TfIc…Rllo) - Sending keepalive packet
DEBUG: [WG-kh0] 2025/06/15 14:29:26 peer(TfIc…Rllo) - Receiving keepalive packet
DEBUG: [WG-kh0] 2025/06/15 14:29:29 peer(XsLr…3g0U) - Sending keepalive packet
DEBUG: [WG-kh0] 2025/06/15 14:29:31 peer(TfIc…Rllo) - Sending keepalive packet
DEBUG: [WG-kh0] 2025/06/15 14:29:31 peer(TfIc…Rllo) - Receiving keepalive packet
```

### テスト
#### ping
ネットワークに参加しているnodeのIP:100.100.96.3から、nodeのIP:100.100.96.2に対してICMPを確認してみます
```
pabotesu@win-machine:~/kurohabaki-client$ ping 100.100.96.2
PING 100.100.96.2 (100.100.96.2) 56(84) bytes of data.
64 bytes from 100.100.96.2: icmp_seq=1 ttl=64 time=102 ms
64 bytes from 100.100.96.2: icmp_seq=2 ttl=64 time=238 ms
64 bytes from 100.100.96.2: icmp_seq=3 ttl=64 time=150 ms
^C
--- 100.100.96.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2109ms
rtt min/avg/max/mdev = 101.696/163.272/238.285/56.565 ms
pabotesu@win-machine:~/kurohabaki-client$
```
100.100.96.2側でも受信を確認できました。
```
pabotesu@kh-client:~$ sudo tcpdump -i kh0 icmp
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on kh0, link-type RAW (Raw IP), snapshot length 262144 bytes
14:30:54.814115 IP 100.100.96.3 > kh-client: ICMP echo request, id 526, seq 1, length 64
14:30:54.814131 IP kh-client > 100.100.96.3: ICMP echo reply, id 526, seq 1, length 64
14:30:55.972220 IP 100.100.96.3 > kh-client: ICMP echo request, id 526, seq 2, length 64
14:30:55.972236 IP kh-client > 100.100.96.3: ICMP echo reply, id 526, seq 2, length 64
14:30:56.992273 IP 100.100.96.3 > kh-client: ICMP echo request, id 526, seq 3, length 64
14:30:56.992290 IP kh-client > 100.100.96.3: ICMP echo reply, id 526, seq 3, length 64
```

### P2Pテスト

サーバ側を落としてみます
```
root@vultr:~/kurohabaki-server# ./kh-server-linux run --config ./config.yaml
Using config file: ./config.yaml
2025/06/15 05:14:49 kurohabaki-server starting...
2025/06/15 05:14:49 Server will listen on 198.xxx.xxx.xxx:5yyyy
2025/06/15 05:14:49 WireGuard interface IP: 100.100.96.1
2025/06/15 05:14:49 Allocated subnet range: 100.100.96.0/24
2025/06/15 05:14:49 WireGuard interface 'kh0' configured
2025/06/15 05:14:49 etcd endpoint: localhost:2379
2025/06/15 05:14:49 Registered self (XsLrrIyasNoSa6ypyOkVscSzsZaOWYAu3nRyKhr3g0U=) with IP 100.100.96.1 in etcd
2025/06/15 05:14:49 Added peer 0xKh+SpOtlENMj+KrssWL7hiOWjE6rFyKjbYOKVR7zg= with IP 100.100.96.2
2025/06/15 05:14:49 Added peer TfIcQ2IvIYbBUr5k5pw12Fsj5CGXRA558nRTLeXRllo= with IP 100.100.96.3
2025/06/15 05:14:49 Started peer endpoint observation loop


^C2025/06/15 05:32:55 Received signal: interrupt
2025/06/15 05:32:55 Stopping embedded etcd...
2025/06/15 05:32:55 🛑 Stopping embedded etcd...
2025/06/15 05:32:55 etcd stopped successfully.
2025/06/15 05:32:55 leaning up WireGuard interface...
2025/06/15 05:32:55 Interface kh0 deleted
2025/06/15 05:32:55 Exiting...
root@vultr:~/kurohabaki-server#
```

サーバ側でwireguardが起動していないことを確認します。
```
root@vultr:~/kurohabaki-server# wg
root@vultr:~/kurohabaki-server#
```

クライアント側でも接続不可のエラーがでます
```
{"level":"warn","ts":"2025-06-15T14:35:29.659352+0900","logger":"etcd-client","caller":"v3@v3.6.1/retry_interceptor.go:65","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0xc0003281e0/100.100.96.1:2379","method":"/etcdserverpb.KV/Range","attempt":0,"error":"rpc error: code = DeadlineExceeded desc = context deadline exceeded"}
2025/06/15 14:35:29 ❌ Failed to fetch peers from etcd: failed to fetch peers from etcd: context deadline exceeded
```

しかし、依然node間の疎通は保たれます。
```
pabotesu@win-machine:~/kurohabaki-client$ ping 100.100.96.2
PING 100.100.96.2 (100.100.96.2) 56(84) bytes of data.
64 bytes from 100.100.96.2: icmp_seq=1 ttl=64 time=57.9 ms
64 bytes from 100.100.96.2: icmp_seq=2 ttl=64 time=288 ms
64 bytes from 100.100.96.2: icmp_seq=3 ttl=64 time=75.1 ms
64 bytes from 100.100.96.2: icmp_seq=4 ttl=64 time=338 ms
^C
--- 100.100.96.2 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3157ms
rtt min/avg/max/mdev = 57.933/189.747/337.568/124.581 ms
pabotesu@win-machine:~/kurohabaki-client$
```
```
pabotesu@kh-client:~$ sudo tcpdump -i kh0 icmp
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on kh0, link-type RAW (Raw IP), snapshot length 262144 bytes
14:35:29.213527 IP 100.100.96.3 > kh-client: ICMP echo request, id 529, seq 1, length 64
14:35:29.213559 IP kh-client > 100.100.96.3: ICMP echo reply, id 529, seq 1, length 64
14:35:30.373540 IP 100.100.96.3 > kh-client: ICMP echo request, id 529, seq 2, length 64
14:35:30.373557 IP kh-client > 100.100.96.3: ICMP echo reply, id 529, seq 2, length 64
14:35:31.332646 IP 100.100.96.3 > kh-client: ICMP echo request, id 529, seq 3, length 64
14:35:31.332662 IP kh-client > 100.100.96.3: ICMP echo reply, id 529, seq 3, length 64
14:35:32.577507 IP 100.100.96.3 > kh-client: ICMP echo request, id 529, seq 4, length 64
14:35:32.577523 IP kh-client > 100.100.96.3: ICMP echo reply, id 529, seq 4, length 64
```
以上でサーバを経由した接続ではないことがわかります。

## まとめ
本稿では、WireGuard を用いた NAT トラバーサル対応の P2P 通信構成を実装してみました。STUN サーバを使わず、WireGuard 経由で得られる接続情報（endpoint）を活用することで、シンプルかつ暗号化された状態で通信経路を構成できるのが大きな特徴です。

この方式は、構成が最小限で済み、すべての経路が WireGuard によって暗号化されるため、セキュアかつ管理しやすいネットワークを実現できます。

一方で、Tailscale などの成熟した VPN プロダクトと比較すると、Symmetric NAT には現時点で対応していないという課題があります。ただし、AllowedIPs の設定を切り替えることで、サーバ中継経由の通信にフォールバックさせることも可能であり、今後の拡張として検討の余地があります。

また、この方式の根本的な前提として、UDP による通信が可能であることが必要です。そのため、企業ネットワークや官公庁など、UDP 通信が制限されている環境では利用できないケースがある点には注意が必要です。TCP のみが許可されたネットワークにおいては、本方式による P2P 接続は成立しません。

今後は、これらの制約への対応やフォールバック機構の追加も視野に入れつつ、より実運用に近い形へのブラッシュアップを進めていきたいと考えています。

## 参考
- https://tailscale.com/blog/how-tailscale-works
- https://tailscale.com/blog/how-nat-traversal-works
- https://tailscale.com/kb/1232/derp-servers
- https://nordsecurity.com/blog/reaching-beyond-1gbps
- https://gist.github.com/voluntas/ae72f30a5bf8db7918cd2237edd3fc50
- https://zenn.dev/voluntas/scraps/82b9e111f43ab3
- https://pkg.go.dev/tailscale.com/wgengine/magicsock
- https://pdos.csail.mit.edu/papers/p2pnat.pdf
