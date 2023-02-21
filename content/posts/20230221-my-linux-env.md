---
title: "小生のLinux環境（+所感）"
date: 2023-02-21T11:06:49Z
tags: ["linux","environment"]
comments: true
showToc: true
---

## 小生のLinux環境

### OS
- Linux ディストリビューション：[Arch Linux](https://www.archlinux.jp/)

### ディスクトップ環境
- グラフィカルセッション：[wayland](https://swaywm.org/)
- ウィンドウマネージャ：[swaywm](https://swaywm.org/)
- ディスプレイマネージャ：[lightdm](https://github.com/canonical/lightdm)  
(lightdm lightdm-webkit2-greeter lightdm-webkit-theme-litarvan)

#### ツール郡
- ステータスバー：[waybar](https://github.com/Alexays/Waybar)
- ランチャー：[wofi](https://github.com/Alexays/Waybar)
- ターミナル：[Alacritty](https://github.com/alacritty/alacritty) & [tmux](https://github.com/tmux/tmux/wiki)
- エディター：[vim](tmux) & [vscode](https://github.com/tmux/tmux/wiki)
- 画面ロック：[swaylock-effects](https://github.com/mortie/swaylock-effects)
- 通知デーモン：[mako](https://github.com/emersion/mako)
- 各種通知バー：[wob](https://github.com/francma/wob)
- ブラウザ：[google-chome](https://www.google.com/intl/ja_jp/chrome/)
- shell：[zsh](https://www.zsh.org/) ※装飾は[prezto](https://github.com/sorin-ionescu/prezto)
- dotfileの管理：[chezmoi](https://www.chezmoi.io/)


#### 音響周り
- [pipewire](https://pipewire.org/)を使ってます
- インターフェース：[puleseaudio](https://wiki.archlinux.jp/index.php/PulseAudio)
- イヤホン：[cyberblade](https://www.angrymiao.com/cyberblade/)※世界中のみんな、これ買え。


(2023/02/21現在、とりあえずここまで追記予定)
![20230221-desktopenv](/img/20230221-linux-env/20230221-210508_grim_area.png)

### configファイル
https://github.com/pabotesu/dotfiles

### 所感
Nixへの移行を考えよう！！！
