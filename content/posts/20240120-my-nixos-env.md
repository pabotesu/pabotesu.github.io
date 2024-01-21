---
title: "20240120 My NixOS Env"
date: 2024-01-20T01:30:07+09:00
tags: ["Linux","Nix","environment"]
comments: true
showToc: true
---
# Nixという山に登る

## 注意点

本稿はNixで自身のデスクトップ環境を構築した際のお話となります。  
文章内ではあくまで当方の認識や考え等も述べている箇所もございますが、齟齬等ございましたら優しくご指摘いただければ大変助かります。  
また、本稿には他の技術に対する意見や他人の感想などが記載されている箇所もあり、気分を害する場合にはブラウザバックを推奨いたします。  

（※筆者の意見ではございますが、様々な技術には一長一短があり、その特定の技術だけが全面的に優れている等は一切思っておりません。  
「○○は最高！！」などと口走ってしまうことはありますが...）

ここまでOKであれば、どうぞ以下よりご一読いただければ幸甚の限りでございます。


## はじまり

恐れながら、人は冒険に出発するとき、ある程度の理由付けが必要なものと思います。  
例えば、「なんとかマスターになるために電気ネズミと故郷にサヨナラバイバイする」とか、  
「人間のことを知りたいから北方の天国に行くエルフ」とか、  

当方の場合、趣味であるデスクトップ盆栽の同士が集う掲示板で、とある画像が投稿されたことがきっかけです。

![20240120-nix_vs_arch](/img/20240120-nix-env/nix_vs_arch.png)

そうです、めちゃめちゃ煽られました。  

私は以前にも[記事](https://pabotesu.dev/posts/20230221-my-linux-env/)にしておりましたが、
メインの環境はArch Linuxを利用しておりました。  
Arch Linuxは非常ミニマムな構成で、多くのパッケージの最新バイナリが圧倒的に早く降ってくる、  
大変クレバーで攻めた印象を受けるLinuxディストリビューションと思っております。  
自分としてはその環境に大変満足していましたし、不自由はないものでした。  
（※今も非常に優れた選択肢の一つと思っております。）  

上記の画像を見た際には気分を害しましたし、他の技術を風刺しているのが見るに耐えませんでした。  
しかし、上記の画像を真っ向から言い返せるほどのバックボーンもなければ、その風刺に対して心当たりがあったのも事実です。
- 気づけば肥大化している`.dotfiles`
- その場しのぎのスクリプト
- 日に日に増えていく埋もれた依存関係たち
- etc..etc..

これらの問題が解決できるのであれば、それはそれはどれほど素晴らしいものか...!  
そもそも、食わず嫌いはよくないね...

**よろしい、ならば使ってみよう...!**

## Nixについて

前ふりが長くなり申し訳ありません、、、  
ここからが本題です。

### Nis is 何

Nixとは...  
正直様々な機能があり過ぎて説明しきることができませぬ、、、  
ラテン語では結晶の意を称し、その多くはクロスプラットフォームのパッケージマネージャーを指し示す場合が多い印象です。  
しかし、その実ビルドツールのような機能を有していたり、IaCのような特性を持っております。  
他のパッケージマネージャーと比較した際に最も特徴的な点としては環境の再現性が非常に高いところにあります。  
その再現性の高さに貢献している機能として、`Derivation`と`Nix store`があります。

`Derivation`とはNixがパッケージを導入する際に必要となる情報や要素が定義されているものとなります。  
例えば、依存関係、ソースコード、ビルドスクリプト、環境変数、アーキテクチャなどなど、、、  
こちらを入力として最終的な出力を生成しパッケージとしてビルドします。

ビルドされたパッケージは`/nix/store`以下にハッシュ値を与えられ格納されます。  
ちなみに、/nix/store配下にビルド後のパッケージと一緒に格納されている`drv`がつくファイルがDerivationとなります。
```
❯ ls /nix/store | grep openssh
0f1agkdv114rpvvr8j8vgsnn5pqrqijz-openssh-9.6p1/
4hlaavjnynzjcm9rah9bnsbmq1dfj4k5-openssh-9.6p1.drv
6r07d5qllsgxc8hkmzdwp24v5xi41fwm-openssh-9.5p1.tar.gz.drv
gad46bs131izbnnj15jci4cr2kizcykj-openssh-9.6p1.drv
jdccr7jfbbamylm1b7i03zyigh1352zv-openssh-9.6p1.tar.gz.drv
jh340w9s38fkzzvz6g02a96xlja70qiy-openssh-9.6p1.drv
l9ypx9ry9x3pkk8xfvr2r9lxpla6a00d-openssh-9.6p1/
qcgly1g00dg1d5in91gg79gsh5gpq14f-openssh-9.6p1.tar.gz.drv
s3b4janyjwf7jac928n0dcp6fy3j5gh7-openssh-9.5p1/
y1i4d6803nxhvd0d0r39h6fyp9lbdlwj-openssh-9.5p1.drv
```
ここで複数のバージョンのopensshが格納されているのが気になります。  
Nixでは異なるバージョンのパッケージをインストールするとDerivationの入力が変わるため、出力されるパッケージも異なります。  
このように同じパッケージでも様々なバージョンがもろとも共存している状態となります。  
また、同バージョンのパッケージが存在していても、`Derivation`では入力以外の要素はビルドに影響を与えることができないため、  
全くの別物として動作しております。  
実はこの導線のおかげで*暗黙的依存の排除*が可能となります。

![20240120-nix_drv_store](/img/20240120-nix-env/nix_drv_store.png)

なお、`Derivation`ファイル自体は人間が直接アクセスするものではなく、実際の定義はNix言語で記述しNix式を用いて実装されます。

以上、基本的な部分の説明とはなりましたが、導入部分だけでも非常に多くの要素があるため、  
今回は環境構築やこのブログ執筆に利用した機能について重点的に説明させていただきます。

- Flakes
- Home-Manager
- nix-shell(nixコマンドのnix shellとnix develop)

### Flakes

`Flakes`はNixのプロジェクト管理機能となります。  
また、Gitとの併用を前提とされており、`flake.nix`を配置することで有効となる機能です。  
Flakesは比較的新しい機能となり、現在Nixは機能更新の過渡期にいるようです。  
以前はChannelsなるものがあったらしい、、、  

flake.nixはGitリポジトリ等を指定するinputとNix式を定義するoutputで構成されます。  
今回のデスクトップ環境もこちらの機能を利用して定義しており、後述するHome-Managerと組み合わせて、  
プロジェクトとして管理しています。

以下については`Flakes`,`Home-Manager`,`nix-shell`を利用した際の当方の構成例となります。

- `Flakes`ではNixが導入されたホスト上でinit的に動作しておいてほしい普遍的なサービスやパッケージの導入（sshやgit,DisplayManager等その他各ホスト別に必要なパッケージなど）を定義しております。  
インターネットの海を徘徊していると、`configuration.nix`をいじる手法が多く取り上げられていますが、  
当方の環境の場合はその役割をFlakesに移譲しております。

- `Home-Manager`では各ユーザ単位で設定されておいてほしいサービスやツール（WindowManagerやshell,エディター）などを定義しています。

- `nix-shell`では各開発環境を定義しております。  

なので定義された環境のスコープを順番に縮小させていくと、Flakes → Home-Manager → nix-shellとなります。

![20240121-nix_env_definition](/img/20240120-nix-env/nix_env_definition.png)

### Home-Manager

前述の通り、Home-Managerはホストに存在する対象のユーザ上で設定されていてほしい項目やパッケージ・ツール等を定義しております。  
具体的にはroot権限が必要な設定はできませんが、ユーザー環境の設定(dotfileなど)に関してはより柔軟な設定が可能となります。  

### nix-shell(nixコマンドのnix shellとnix develop)

個人的にNixを使うにあたり最も楽しみにしていた機能です。

前述の通りNixではDerivationを用いて様々なものを定義することが可能です。  
この機能は非常に細かい単位でも実行可能なため、例えば特定のディレクトリレベルに必要な環境を定義したファイル  
（shell.nix, default.nix, flake.nixこの辺のファイルを導入するとよきです。）をディレクトリに配置しておけば、  
そのディレクトリの中でのみ、必要なパッケージ・モジュール・環境変数などが組まれたshellをあっという間に用意してくれます。

こちらの機能のnixコマンド版が、`nix shell`と`nix develop`となります。  
※nix <subcommand>の形で提供されるコマンド体系はNix commandと呼ばれます。  
　Nix commandは内部でFlakesを利用するようになっており、再現性の向上が見込まれます。  
※nix 2.4からnixコマンドに全ての機能を集約する変更が加えられたようです

主に`nix shell`は`nix-shell -p <パッケージ名>`でその対象のパッケージが導入されたインスタントなshellを提供してくれます。  
`nix develop`では例のごとく利用したい環境を定義したファイルをあらかじめ用意すると、その環境が構築されたshellを提供します。

具体的な例を以下に示します。

今回は本稿を記述するにあたりhugoが導入された状態のshellを用意する必要があります。  
よって以下を定義しております。  
こちらのファイルは当該リポジトリのルートディレクトリに配置しております。
```
❯ cat flake.nix
───────┬─────────────────────────────────────────────────────────────────────────────────
       │ File: flake.nix
   1   │ {
   2   │   inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";
   3   │
   4   │   outputs = inputs: let
   5   │     pkgs = import inputs.nixpkgs {
   6   │       system = "x86_64-linux";
   7   │     };
   8   │   in {
   9   │     devShells."x86_64-linux".default = pkgs.mkShell {
  10   │       buildInputs = with pkgs; [
  11   │         hugo
  12   │       ];
  13   │     };
  14   │   };
  15   │ }
───────┴─────────────────────────────────────────────────────────────────────────────────

```

また、予め同ディレクトリに以下の`.envrc`も配置し`use flake`を記載、
`direnv allow`とdirenvを有効化します。  
（こちらは事前に[nix-direnv](https://github.com/nix-community/nix-direnv)を導入しておきます。）
```
───────┬─────────────────────────────────────────────────────────────────────────────────
       │ File: .envrc
───────┼─────────────────────────────────────────────────────────────────────────────────
   1   │ use flake
───────┴─────────────────────────────────────────────────────────────────────────────────
```

リポジトリのディレクトリに移動した瞬間、一気に機能が有効化し、  
hugoが利用可能な状態となりました。
```
Src/github.com/pabotesu
❯ cd pabotesu.github.io
direnv: loading ~/Src/github.com/pabotesu/pabotesu.github.io/.envrc
direnv: using flake
direnv: nix-direnv: using cached dev shell
direnv: export +AR +AS +CC +CONFIG_SHELL +CXX +HOST_PATH +IN_NIX_SHELL +LD +NIX_BINTOOLS +NIX_BINTOOLS_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu +NIX_BUILD_CORES +NIX_CC +NIX_CC_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu +NIX_CFLAGS_COMPILE +NIX_ENFORCE_NO_NATIVE +NIX_HARDENING_ENABLE +NIX_LDFLAGS +NIX_STORE +NM +OBJCOPY +OBJDUMP +RANLIB +READELF +SIZE +SOURCE_DATE_EPOCH +STRINGS +STRIP +__structuredAttrs +buildInputs +buildPhase +builder +cmakeFlags +configureFlags +depsBuildBuild +depsBuildBuildPropagated +depsBuildTarget +depsBuildTargetPropagated +depsHostHost +depsHostHostPropagated +depsTargetTarget +depsTargetTargetPropagated +doCheck +doInstallCheck +dontAddDisableDepTrack +mesonFlags +name +nativeBuildInputs +out +outputs +patches +phases +preferLocalBuild +propagatedBuildInputs +propagatedNativeBuildInputs +shell +shellHook +stdenv +strictDeps +system ~PATH ~XDG_DATA_DIRS

pabotesu.github.io on  main [!?⇡] via  impure (nix-shell-env)
❯ hugo version
hugo v0.121.2+extended linux/amd64 BuildDate=unknown VendorInfo=nixpkgs
```

しかし、一つ上のディレクトリに移動したところ、hugoは`hugo: command not found`となり、そんなものはありません。  
*なんだ、ただの幻か...*
```
pabotesu.github.io on  main [!?⇡] via  impure (nix-shell-env)
❯ cd ..
direnv: unloading

Src/github.com/pabotesu
❯ hugo version
hugo: command not found
```

このようにグローバルな環境を汚すことなく、あっという間にほしい環境を起こし、そこにchange directoryするだけで簡単にお邪魔することができるわけです。  

この機能、
- ペライチで環境を用意できる
- 用意した環境をメンバーに簡単に共有できる
- 開発環境などでパッケージのバージョン等を統一できる

などなど、Docker等のコンテナ技術による開発環境の提供に非常に近いものがあります。  
しかし、Dockerなどではその環境に入る際、別のサーバにアクセするような動線を持ってshellを叩くため、  
自身が今まで用意したshell環境・vimの設定などを利用することが難しくなります。  
つまり、積み上げてきたパワーが利用できないわけです。

しかし、`nix develop`の場合、あくまで今まで使っていた環境に利用したい構成が付与されているような状態となるため、  
さながら未来のひみつ道具である「も○もボックス」のようにパラレルな環境と同居できるわけです。  
よっていままで積み上げてきたパワーは引き継げ、よりスムースな開発環境の移行が可能となります。  
（※もちろん、現在の環境を引き継がないような設定も可能です）

## NixOS

ここまでNixの機能についてお話ししてまいりましたが、  
「Nixってたしかに便利だけど、クロスプラットフォームのパッケージマネージャーなら他のディストロやWindowsのWSL、Macでも使えるってこと？」  
と疑問をお持ちのことでしょうか。

ご認識の通り、他ディストロやWSL、Macでも工夫をすれば容易に利用可能なためArch LinuxでもNixは叩けますし、  
それは非常にクレバーな選択肢となるでしょう。

しかしながら、他よりも増してNixのエコシステムにうまく組み込まれているOSがございます。  
それが`NixOS`となります。

NixOSの特徴は以下のようなものがあります。

- root権限が必要な領域の設定も定義が可能
- NixOS modulesが利用可能(Nix言語を用いて環境を宣言的に記述する機能)
- ロールバック機能

root権限が必要な領域などもFlakesに組み込み、かつmodulesで各役割ごとに定義できるのは非常に大きな力となるでしょう。  
可読性も増しますし、何よりもOSレベルの設定を他ホストなどで再利用可能となります。

そして、当方が最も素晴らしいと感じている機能として、ロールバック機能が挙げられます。  
他ディストロでもそうですが、とあるパッケージのアップデートを行ったら二度とOSが起動しなくなった、、、  
などの経験はございますでしょうか。  
NixOSではブートローダーから過去の環境をロールバックすることができます。

*過去に戻れるとは、やはりNixOSはドラ○もんであったか...*

## 最後に

ここまでNix及びNixOSの機能を絶賛してまいりましたが、  
前段でも述べているように、対象の技術が他を圧倒して完璧に優れているなどはありえません。  

なにものも必ず痛みを伴います。

例えば、
- 習得難易度が高い
- nix-pkgsで用意されているパッケージは細かい設定まで簡単に定義できるけど、そうではないサービスやパッケージは定義が大変、てか地獄
- モジュール導入周りのお行儀が悪い言語などで開発環境を建てようとするとこれまた地獄
- リファレンスの情報が古かったり、英語の方言（Nixはヨーロッパ圏で盛んなようで英語の書きなまりがすんごい）で辛い

などなど、挙げたら良いところと同じくらいにはきりがないのです、、、

しかし、比較的歴史もあり、活動も非常に活発なOSSとなりますので、  
皆様もぜひお試しいただければと思います！

参考にしたリポジトリや先行者の皆様のdotfilesに比べればまだまだの部分も多く、  
お見苦しいものではございますが、本稿の成果物となりますので、ご査収ください
[pabotesu/dotfiles](https://github.com/pabotesu/dotfiles)

それでは、皆様のNixライフに幸多からんことをを祈りまして、稿を閉じさせていただきます。  
※指摘とか書きたいことが追加であれば普通に追記しますが、、、

## 参考
- [NixOSで最強のLinuxデスクトップを作ろう](https://zenn.dev/asa1984/articles/nixos-is-the-best#%E7%97%9B%E3%81%BF)  
本当にスペシャルサンクスです！  
この記事がなければNixに移行しようなんて思わんかったし、Nixについて日本語でまとまってる記事ではトップレベルです。  
pabotesuの記事なんて読まず、同記事を読め！

- [Nixでlinuxとmacの環境を管理してみる](https://blog.ymgyt.io/entry/declarative-environment-management-with-nix/)  
こちらも本当に参考になりました。  
こちらも日本語として非常によくまとまっている記事と思います。  

- [NixOS & Nix Flakes - A Guide for Beginners](https://thiscute.world/en/posts/nixos-and-flake-basics/)  
ここもとんでもねぇ、、、

- [How to Learn Nix](https://ianthehenry.com/posts/how-to-learn-nix/)  
Nixの掘り方が結構わかる。この人の調査証跡は本当に尊敬してます。

- 手始めに概念や使用感はこちらである程度把握できそう
  - [NixOS Wiki](https://nixos.wiki/wiki/Main_Page)  
  - [Nix Reference Manual](https://nixos.org/manual/nix/stable/introduction.html)  
  - [Zero to Nix](https://zero-to-nix.com)  
  - [フォーラム](https://discourse.nixos.org)  

- パッケージやHome-Managerのオプションで迷子になったら、こちらを参考にしてます。
  - [NixOS search](https://search.nixos.org/packages)
  - [home-manager-option-search](https://mipmip.github.io/home-manager-option-search/)

- 各種リポジトリ
  - [NixOS/nix](https://github.com/NixOS/nix)
  - [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs)
  - [NixOS/nixos-hardware](https://github.com/NixOS/nixos-hardware)


- 参考にした構成例
  - [asa1984/dotfiles](https://github.com/asa1984/dotfiles)
  - [fufexan/dotfiles](https://github.com/fufexan/dotfiles)
  - [Misterio77/nix-config](https://github.com/Misterio77/nix-config)
  - [Ruixi-rebirth/flakes](https://github.com/Ruixi-rebirth/flakes)

あとは、redditとかでもろもろ記事などを漁ってました。