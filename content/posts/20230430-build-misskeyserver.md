---
title: "20230430 Build Misskeyserver"
date: 2023-04-30T12:07:41Z
tags: ["misskey","linux"]
comments: true
showToc: true
---

## Misskeyサーバを実装する

### 実装について

- 実装対象：misskeyサーバ
- 利用リソース：自宅サーバ、cloudflare
- ハイパバイザ：proxmox

### 実装の流れ

1. proxmox上に仮想マシン立ち上げ、misskeyサーバを構成する
2. cloudflareにてCDN設定

### 構成（実装例）
https://thxdaddy.xyz/

---

1\. proxmox上に仮想マシン立ち上げ、misskeyサーバを構成する

- 以下参考にmisskeyサーバを実装いたしました。
[Misskey構築の手引き](https://misskey-hub.net/docs/install/manual.html)

- proxmoxの様子
![20230607-194100_proxmox](/img/20230430-build-misskeyserver/20230607-1941_proxmox.png)

2\. cloudflareにてCDN設定

- 以下のようにCloudFlare`Zero Trust`のTunnnelを設定
![20230607-2053_cloudflare](/img/20230430-build-misskeyserver/20230607-2053_cloudflare.JPG)

- その後、`1. proxmox上に仮想マシン立ち上げ、misskeyサーバを構成する`
にて実装したサーバに`cloudflareのAPI`のインストールと
`設定したトンネルの接続コマンド（設定時提示されます。）`を実行します。

- 基本的に以上でサーバを公開できます。

### 実装後

- これで一国一城の主となったわけです・・・

### おまけ

- Misskey v13でAn error has occurred!が発生する
![20230607-2051_misskeyerror](/img/20230430-build-misskeyserver/20230607-2051_misskeyerror.png)

  - 以下記載のようにCloudflareのAuto Minifyの影響のようです。
    - CloudFlareで構成ルール等を使ってAuto Minifyをオフにすると解決します。

    [Misskey is not opening properly in 13.3.1 #9791](https://github.com/misskey-dev/misskey/issues/9791)

- 実際に動いてるサーバくん

![20230206_1910_runningserver](/img/20230430-build-misskeyserver/20230206_1910_runningserver.jpg)

### 参考
- [Misskey構築の手引き](https://misskey-hub.net/docs/install/manual.html)