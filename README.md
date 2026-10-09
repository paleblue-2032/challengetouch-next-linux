# Challenge Touch NEXT に Linux を入れる (challengetouch-next-linux)

Benesse「チャレンジパッド NEXT」こと **TAB-A05-BA1**（codename `a05ba`, MediaTek MT8168A）で、
Android を消さずに **recovery スロットへ自作 Linux を焼いて起動**し、
**microSD 上の永続 Alpine rootfs + X デスクトップ**を自動起動させるまでの作業メモと一式です。

開発端末から USB 経由（ACM シリアル / RNDIS ネットワーク / SSH）で操作でき、
画面には icewm + xterm のデスクトップが出ます。日本語表示・タッチ・ペン入力にも対応しています。

```
 +--------------------+        USB (RNDIS)         +----------------------+
 | ホスト PC (Linux)   | <=== 10.0.0.1 <-> 10.0.0.2 ==> | チャレンジパッド NEXT |
 |                    |        + ACM serial          |  recovery slot: Linux |
 +--------------------+                              +----------+-----------+
                                                                |
                                                        microSD (ext4)
                                                        /linux-root  Alpine
```

## ハードウェア / デバイス情報（実測）

| 項目 | 内容 |
| --- | --- |
| 型番 / codename | TAB-A05-BA1 / `a05ba`（シリアル `REDACTED`） |
| SoC | MediaTek MT8168A（4x Cortex-A53 @2.001GHz）, GPU Mali-G52 MC1 |
| PMIC / RAM | MT6357 / 4GB |
| ストレージ | eMMC 16GB (`mmcblk0`) + microSD (`mmcblk1`) |
| 画面 | 1920x1200 DSI（`auo_wuxga_incell_dsi` / `kd_wuxga_incell_dsi`） |
| タッチ / ペン | Novatek `nt36xxx`（`novatek,NVT-ts`） |
| 無線 | CONSYS_8168（WiFi/BT, SDIO） |
| カーネル | Linux 4.14.87+（MTK downstream, 2022-12-08 build） |
| 元 OS | Android 9 (API28), A-only 単一スロット, ブートローダー unlock 済み |
| 現在の ROM | REDACTED v2.1.0（Pixel 3a `sargo` を偽装） |

## 全体の仕組み

1. **Linux は `recovery` パーティション (p15) に入る。** `boot` (p14) は純正 Android のまま無傷。
   普通に電源を入れると Android が起動し、`recovery` 起動を指定したときだけ Linux が起動する。
2. 起動イメージは「既知の起動可能イメージ（TWRP `a05ba-tate.img`）の **ramdisk だけ差し替え**」で作る。
   `mkbootimg` でゼロから作ったイメージは、この LK が要求する **recovery_dtbo + AVB フッター構造**を
   欠くため受け付けられない（起動直後にリセットする）。詳細は `build_linux_img.sh` のコメント参照。
3. 自作 **initramfs (`work/initramfs-root/init`, v9)** が起動直後にやること:
   - `/dev`・`/proc` 等をマウント、udev 前段の準備
   - CPU watchdog への給餌スレッドを回す（MTK の再起動回避）
   - **USB ガジェット**を作成 = `acm`（`/dev/ttyACM0` シリアル）+ `rndis`（ネット `10.0.0.2`）
   - microSD (`/dev/mmcblk1p1`) を ext4 でマウント。初回は `alpine.tar.gz` を `/mnt/sd/linux-root` へ展開
   - `/mnt/sd/linux-root` に bind mount して **chroot** し `/usr/local/bin/cpad-boot` を実行
4. rootfs 側 `/usr/local/bin/cpad-boot`（SD 上なので**リフラッシュ不要**で編集可）が:
   - **udev** 起動（X が入力デバイスを列挙するのに必須）
   - RNDIS に `10.0.0.2/24` を設定、`dropbear` SSH (:22) を起動
   - **Xorg (fbdev) + icewm + xterm** を起動。`cpad-gui` がスーパバイザとして常駐し
     X が落ちても自動復帰する（このカーネルでは `pgrep -x Xorg` が効かないため PID 管理）

> 注意: `fastboot boot <img>` は**使えない**。この MTK LK はどのイメージでも約 23 秒で
> リセットする（MTK ブート用ウォッチドッグ）。**必ずフラッシュして通常起動**すること。

## ディレクトリ構成

```
.
├── README.md                 … このファイル
├── AGENTS.md                 … 作業引き継ぎメモ（詳細な落とし穴・経緯）
├── RECOVER.txt               … Android へ戻す手順
├── boot_recovery.sh          … 端末を Linux(recovery) で起動する
├── host_net.sh               … ホスト側 RNDIS 設定 (10.0.0.1/24 + NAT)
├── build_linux_img.sh        … 既知イメージの ramdisk 差し替えで起動イメージを作る
├── make_boot_twrp.sh         … TWRP カーネル + 自作 ramdisk の boot イメージを作る（旧経路）
├── boot_linux.sh             … ビルド→fastboot で recovery へ焼く（参考）
├── flash_linux_recovery.sh   … fastboot で recovery へ焼いて起動（参考）
├── shell.nix                 … カーネルビルド用 FHS 環境（将来用）
├── next.dts / dtbo_next.dts  … Next の DTS / DTBO ソース
├── next_appended.dtb         … カーネルに付ける DTB
├── kernel_Image.gz           … 純正カーネル blob（boot イメージ組み立て用）
├── nix/                      … ホスト補助（sudo/udev 設定など）
├── twrp/                     … ベースにする TWRP イメージ（a05ba-tate.img のみ追跡）
└── work/
    ├── initramfs-root/       … ★ initramfs のステージング（init + alpine.tar.gz）
    ├── initramfs_alpine_v9.cpio.gz … ★ ビルド済み initramfs（現行 v9）
    ├── linux_v9.img          … ★ 現行の起動イメージ（recovery へ焼く実体）
    ├── busybox-aarch64       … initramfs に同梱する静的 busybox
    ├── device/               … ★ SD rootfs に置く設定一式（cpad-boot / cpad-gui / X 設定）
    ├── remote/               … 実機スクリーンショット
    ├── push_device.sh        … device/ を SD rootfs へ同期
    ├── ssh.sh                … 端末へ SSH
    ├── enter_fastboot.sh / mtk-bootseq.py … preloader から fastboot へ
    ├── serial_*.py           … USB シリアル経由の操作（SSH 不通時の保険）
    └── twrp_cmdline.txt / twrp_appended.dtb / twrp_recovery_dtbo.bin … TWRP から抽出した素材
```

★ = 再現の要となるファイル。

## 使い方（Linux を起動して入る）

```sh
# 1. 端末を Linux で起動
bash boot_recovery.sh

# 2. ホスト側ネット設定（端末を起動するたびに 1 回。IP が消えたら再実行）
sudo bash host_net.sh

# 3. 端末へログイン
work/ssh.sh                  # 対話シェル
work/ssh.sh 'uname -a'       # 単発コマンド
```

USB シリアル（`/dev/ttyACM0`）も使えます（SSH が不通なときの保険）:

```sh
nix-shell -p python3 python3Packages.pyserial --run \
  'python3 work/serial_cmd.py /dev/ttyACM0 "uname -a" "ip a"'
```

## Linux 側を変更する（リフラッシュ不要）

rootfs は SD 上にあるため、`work/device/` を直して同期するだけで反映されます:

```sh
# work/device/ を編集してから
bash work/push_device.sh
```

- `/usr/local/bin/cpad-boot` … 起動時の一式（udev / net / ssh / GUI 起動）
- `/usr/local/bin/cpad-gui` … X デスクトップのスーパバイザ
- `/etc/X11/xorg.conf`, `/etc/X11/xorg.conf.d/{20-touch,60-nvt-pen}.conf`
- `/root/.icewm/preferences`

手動で作り直すとき（端末上で）: `/usr/local/bin/cpad-reset` で停止 → `setsid /usr/local/bin/cpad-gui &`

## 起動イメージを作り直す（initramfs の `init` を変えたとき）

```sh
# initramfs をビルド
nix-shell -p cpio gzip --run '
  cd work/initramfs-root &&
  cp -f ../busybox-aarch64 bin/busybox && chmod 755 bin/busybox init &&
  find . -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null | gzip -9 > ../initramfs_alpine_v9.cpio.gz'

# 起動イメージ = TWRP ベース + 上記 ramdisk（dtbo/AVB フッターは保持される）
bash build_linux_img.sh work/initramfs_alpine_v9.cpio.gz twrp/a05ba-tate.img work/linux_v9.img
```

焼き方:

```sh
# 方法A: Linux 稼働中に recovery パーティション (p15) へ直接書く（速い）
work/ssh.sh 'cat > /root/linux_v9.img' < work/linux_v9.img
work/ssh.sh 'dd if=/root/linux_v9.img of=/dev/mmcblk0p15 bs=1M; sync; rm /root/linux_v9.img'
bash boot_recovery.sh

# 方法B: fastboot 経由
adb reboot bootloader
fastboot flash recovery work/linux_v9.img
fastboot oem reboot-recovery
```

パーティション対応: `boot = mmcblk0p14` / **`recovery = mmcblk0p15`** / `cache = mmcblk0p31`

## Android に戻す

- `boot` (p14) は純正のまま。電源を切って普通に起動すれば Android が起動します。
- recovery を純正に戻す: `fastboot flash recovery REDACTED/Next/files/imgs/recovery.img`
  （純正 recovery イメージは下記「含まれないもの」を参照）
- 詳細は `RECOVER.txt`。

## リポジトリに含まれないもの

リポジトリを軽量に保つため、巨大な純正ファームやカーネルクローンは**追跡していません**
（`.gitignore` 参照）。必要なら各自で入手してください。

| 除外物 | サイズ目安 | 入手先 |
| --- | --- | --- |
| `REDACTED/`, `REDACTED_Next_v2.0.0.zip` | 2.3G / 1.1G | REDACTED ROM: https://REDACTED.org/ , https://github.com/CPadREDACTED/REDACTED |
| `backup/`（実機パーティション吸い出し） | 165M | 各実機から TWRP で吸い出し（復旧用の控え） |
| `a05ba-kernel/` | 1.3G | https://github.com/coara-chocomaru/mt8168_a05ba_kernel |
| `mouseos-a05bd-kernel/`（Neo 用・参照） | 1.2G | https://github.com/mouseos/mt8168_a05bd_kernel |
| `mtkclient/` | 91M | https://github.com/bkerler/mtkclient |
| `twrp/*.img`（`a05ba-tate.img` 以外） | 各 16M | https://github.com/coara-chocomaru/TAB-A05-BA1-Next-TWRP |

## 現状 / 次の一手

- **達成**: 再起動後 3 分以上安定稼働・スクリーンショット確認済み（日本語表示込み, `work/remote/*.png`）。
- 未実施: タッチ実機テスト（必要なら libinput キャリブレーション）。
- 候補: 常用アプリ（GPU 無効ゆえソフトウェアレンダリングの重さに注意）。
- 将来: `boot` (p14) へ焼いて電源だけで起動（**AVB フッター構造必須・要注意**）。
- 別ディストロ: 永続化は SD 上に tarball 展開する方式。`init` の `tar xzf /alpine.tar.gz` を
  別 distro の tarball に差し替えれば入れ替え可能。

## ライセンス / 注意

個人の実験プロジェクトです。本リポジトリには**純正ファームウェアやベンダー由来のバイナリは含まれません**が、
`twrp/a05ba-tate.img` など第三者が配布するイメージを参照用に保持しています。これらは各配布元の
ライセンスに従ってください。作業はすべて自己責任で。

## 参考リンク

- REDACTED: https://REDACTED.org/
- Next カーネルソース: https://github.com/coara-chocomaru/mt8168_a05ba_kernel
- Next 用 TWRP: https://github.com/coara-chocomaru/TAB-A05-BA1-Next-TWRP
- 仕様 (Wiki): https://wiki3.jp/SmileTabLabo/page/14
