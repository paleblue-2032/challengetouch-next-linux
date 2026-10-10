# Challenge Touch NEXT に Linux を入れる (challengetouch-next-linux)

Benesse「チャレンジタッチ NEXT」こと **TAB-A05-BA1**（codename `a05ba`, MediaTek MT8168A）で、
Android を消さずに **recovery スロットへ自作 Linux を焼いて起動**し、
**microSD 上の永続 Alpine rootfs + GNOME デスクトップ**を自動起動させるまでの作業メモと一式です。

開発端末から USB 経由（ACM シリアル / RNDIS ネットワーク / SSH）で操作でき、
**電源を入れると GNOME（Flashback: gnome-panel + metacity）のデスクトップ**が出ます。
日本語表示・タッチ・ペン入力にも対応しています。

```
 +--------------------+        USB (RNDIS)         +----------------------+
 | ホスト PC (Linux)   | <=== 10.0.0.1 <-> 10.0.0.2 ==> | チャレンジタッチ NEXT |
 |                    |        + ACM serial          |  recovery slot: Linux |
 +--------------------+                              +----------+-----------+
                                                                |
                                                        microSD (ext4)
                                                        /linux-root  Alpine
```

## ハードウェア / デバイス情報（実測）

| 項目 | 内容 |
| --- | --- |
| 型番 / codename | TAB-A05-BA1 / `a05ba` |
| SoC | MediaTek MT8168A（4x Cortex-A53 @2.001GHz）, GPU Mali-G52 MC1 |
| PMIC / RAM | MT6357 / 4GB |
| ストレージ | eMMC 16GB (`mmcblk0`) + microSD (`mmcblk1`) |
| 画面 | 1200x1920 DSI 縦パネル（`auo_wuxga_incell_dsi` / `kd_wuxga_incell_dsi`）。UI は縦で運用 |
| タッチ / ペン | Novatek `nt36xxx`（`novatek,NVT-ts`） |
| 無線 | CONSYS_8168（WiFi/BT, SDIO） |
| カーネル | Linux 4.14.87+（MTK downstream, 2022-12-08 build） |
| 元 OS | Android 9 (API28), A-only 単一スロット, ブートローダー unlock 済み |

## 全体の仕組み

1. **Linux は `recovery` パーティション (p15) に入る。** `boot` (p14) は純正 Android のまま無傷。
   LK の起動先は `para` (p16) の BCB コマンド欄で決まり、`ct-next-boot` が毎起動 `boot-recovery` を書き戻すため
   **電源を入れるだけで Linux が起動する**。Android に戻すには Linux 上で `ct-next-android`。
2. 起動イメージは「既知の起動可能イメージ（TWRP `a05ba-tate.img`）の **ramdisk だけ差し替え**」で作る。
   `mkbootimg` でゼロから作ったイメージは、この LK が要求する **recovery_dtbo + AVB フッター構造**を
   欠くため受け付けられない（起動直後にリセットする）。詳細は `build_linux_img.sh` のコメント参照。
3. 自作 **initramfs (`work/initramfs-root/init`, v9)** が起動直後にやること:
   - `/dev`・`/proc` 等をマウント、udev 前段の準備
   - CPU watchdog への給餌スレッドを回す（MTK の再起動回避）
   - **USB ガジェット**を作成 = `acm`（`/dev/ttyACM0` シリアル）+ `rndis`（ネット `10.0.0.2`）
   - microSD (`/dev/mmcblk1p1`) を ext4 でマウント。初回は `alpine.tar.gz` を `/mnt/sd/linux-root` へ展開
   - `/mnt/sd/linux-root` に bind mount して **chroot** し `/usr/local/bin/ct-next-boot` を実行
4. rootfs 側 `/usr/local/bin/ct-next-boot`（SD 上なので**リフラッシュ不要**で編集可）が:
   - **udev** 起動（X が入力デバイスを列挙するのに必須）
   - RNDIS に `10.0.0.2/24` を設定、`dropbear` SSH (:22) を起動
   - **dbus / elogind / polkit** を起動
   - **Xorg (fbdev) + GNOME Flashback** を起動。`ct-next-gui` がスーパバイザとして常駐し
     X と GNOME セッションが落ちても自動復帰する（このカーネルでは `pgrep -x Xorg` が効かないため PID 管理）

> カーネル制約: KMS/DRM (`CONFIG_DRM_MEDIATEK=n`) と VT (`CONFIG_VT=n`) が無いため
> **Wayland や GDM は使えません**。fbdev Xorg は DRI3 無しで EGL/GL も不可のため、
> GL 必須の **GNOME Shell は動きません** → GL 不要の **GNOME Flashback** を DM 無しで手動起動しています。
> タッチはパネル縦(1200x1920)に対し横(1920x1200)座標で来るため 90°変換を当てています（`ct-next-touch` で校正）。

> 注意: `fastboot boot <img>` は**使えない**。この MTK LK はどのイメージでも約 23 秒で
> リセットする（MTK ブート用ウォッチドッグ）。**必ずフラッシュして通常起動**すること。

## ディレクトリ構成

```
.
├── README.md                 … このファイル（これだけで再現・運用が完結）
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
├── kernel/                   … 電源OFF修正版カーネルのパッチ・ビルド・梱包スクリプト
├── twrp/                     … ベースにする TWRP イメージ（a05ba-tate.img のみ追跡）
└── work/
    ├── make_alpine_base.sh   … ★ Alpine ベース + work/device を alpine.tar.gz にビルド
    ├── initramfs-root/       … ★ initramfs のステージング（init + alpine.tar.gz）
    ├── initramfs_alpine_v9.cpio.gz … ★ ビルド済み initramfs（現行 v9）
    ├── linux_v10.img          … ★ 現行の起動イメージ（recovery へ焼く実体）
    ├── busybox-aarch64       … initramfs に同梱する静的 busybox
    ├── device/               … ★ SD rootfs に置く設定一式
    │   ├── etc/X11/…         … X 設定（fbdev / タッチ変換行列）
    │   └── usr-local-bin/    … ct-next-boot / ct-next-gui / ct-next-session / ct-next-touch /
    │                            ct-next-android / ct-next-reset / ct-next-provision
    ├── push_device.sh        … device/ を SD rootfs へ同期（リフラッシュ不要）
    ├── ssh.sh                … 端末へ SSH
    ├── enter_fastboot.sh / mtk-bootseq.py … preloader から fastboot へ
    ├── serial_*.py           … USB シリアル経由の操作（SSH 不通時の保険）
    └── twrp_cmdline.txt / twrp_appended.dtb / twrp_recovery_dtbo.bin … TWRP から抽出した素材
```

★ = 再現の要となるファイル。

## ゼロから再現する（第三者向け）

必要なもの: Linux ホスト（`adb` / `fastboot` / `nix` / `bash`）、端末（ブートローダー unlock 済み・Android 起動可）、
microSD（ext4 1 パーティション）、同梱の `twrp/a05ba-tate.img`。

```sh
# 1. SD 上の Alpine ベースを作る（Alpine minirootfs を取得し work/device/ を焼き込む）
bash work/make_alpine_base.sh                      # ネットから Alpine を取得
# bash work/make_alpine_base.sh /path/base.tar.gz  # 手元の base を使う場合

# 2. カーネル（電源OFF修正版）+ initramfs から起動イメージをビルド
git clone https://github.com/coara-chocomaru/mt8168_a05ba_kernel a05ba-kernel
bash kernel/build-kernel.sh
nix-shell -p cpio gzip --run '
  cd work/initramfs-root &&
  cp -f ../busybox-aarch64 bin/busybox && chmod 755 bin/busybox init &&
  find . -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null | gzip -9 > ../initramfs_alpine_v9.cpio.gz'
cat a05ba-kernel/build/src/kernel/mediatek/mt8168/4.14/arch/arm64/boot/Image.gz \
    next_appended.dtb > /tmp/kernel_with_dtb
python3 kernel/pack-recovery.py /tmp/kernel_with_dtb \
    work/initramfs_alpine_v9.cpio.gz twrp/a05ba-tate.img work/linux_v10.img

# 3. recovery スロットへ焼く（boot/Android は消さない）
adb reboot bootloader
fastboot flash recovery work/linux_v10.img
fastboot oem reboot-recovery

# 4. ホスト側ネット設定（端末を起動するたびに 1 回）
sudo bash host_net.sh

# 5. デスクトップ一式を導入（初回のみ・要インターネット。数百 MB）
work/ssh.sh /usr/local/bin/ct-next-provision
work/ssh.sh 'reboot'           # → GNOME が自動起動

# 6. 以後は電源を入れるだけで Linux(GNOME)。Android へは:
work/ssh.sh /usr/local/bin/ct-next-android
```

> `work/initramfs-root/alpine.tar.gz` には `work/device/`（`ct-next-boot` など）を**焼き込み済み**なので、
> 初回起動の時点で RNDIS ネット＋SSH が上がります。SSH が不通のときは ACM シリアル
> （`/dev/ttyACM0`、`work/serial_*.py`）で入れます。パッケージ一覧は
> `work/device/usr-local-bin/ct-next-provision` に集約しています。

## カーネルから作る（電源OFF修正）

純正カーネルは充電器接続中の `poweroff` を再起動にしてしまうため、`mt_power_off()` の当該分岐を削除した
カーネルを自前でビルドします（`kernel/` 以下に一式）。

```sh
# 1. カーネルソースを取得（「リポジトリに含まれないもの」参照）
git clone https://github.com/coara-chocomaru/mt8168_a05ba_kernel a05ba-kernel

# 2. パッチ適用 + ビルド（nix のクロス GCC。初回は時間がかかります）
bash kernel/build-kernel.sh
#  -> a05ba-kernel/build/src/kernel/mediatek/mt8168/4.14/arch/arm64/boot/Image.gz

# 3. 起動イメージへ再パック（自作カーネル + initramfs を TWRP ベースに載せる）
cat a05ba-kernel/build/src/kernel/mediatek/mt8168/4.14/arch/arm64/boot/Image.gz \
    next_appended.dtb > /tmp/kernel_with_dtb
python3 kernel/pack-recovery.py /tmp/kernel_with_dtb \
    work/initramfs_alpine_v9.cpio.gz twrp/a05ba-tate.img work/linux_v10.img

# 4. 焼く（後述の「焼き方」と同じ）
```

`kernel/ct-next-kernel.patch` には電源OFF修正に加え、旧カーネルを新しい GCC でビルドするための
Makefile 調整（`-Werror` 除去、`$(src)` の include 追加 等）も含まれます。

## 使い方（Linux を起動して入る）

電源を入れるだけで Linux が起動します（`para` の BCB 常設）。ホストから明示的に起動する場合は下記:

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

- `/usr/local/bin/ct-next-boot` … 起動時の一式（udev / net / ssh / dbus・elogind・polkit / GUI 起動 / BCB 再セット）
- `/usr/local/bin/ct-next-gui` … Xorg + GNOME セッションのスーパバイザ
- `/usr/local/bin/ct-next-session` … GNOME セッション起動（`gnome-session --session=ct-next`）
- `/usr/local/bin/ct-next-touch` … タッチ/ペンの回転を切り替えて校正（cw/ccw/180/none）
- `/usr/local/bin/ct-next-android` … Android( boot/p14 )へ戻す（BCB をクリアして再起動）
- `/usr/local/bin/ct-next-provision` … デスクトップ一式を apk で導入（初回セットアップ用）
- `/usr/local/bin/ct-next-reset` … デスクトップ停止（再起動用）
- `/etc/X11/xorg.conf`, `/etc/X11/xorg.conf.d/{20-touch,60-nvt-pen}.conf`

手動で作り直すとき（端末上で）: `/usr/local/bin/ct-next-reset` で停止 → `setsid /usr/local/bin/ct-next-gui &`

## 起動イメージを作り直す（initramfs の `init` を変えたとき）

```sh
# initramfs をビルド
nix-shell -p cpio gzip --run '
  cd work/initramfs-root &&
  cp -f ../busybox-aarch64 bin/busybox && chmod 755 bin/busybox init &&
  find . -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null | gzip -9 > ../initramfs_alpine_v9.cpio.gz'

# 起動イメージ = TWRP ベース + 上記 ramdisk（dtbo/AVB フッターは保持される）
#   ramdisk だけ差し替える場合（純正カーネルのまま）:
bash build_linux_img.sh work/initramfs_alpine_v9.cpio.gz twrp/a05ba-tate.img work/linux_v10.img
#   カーネルごと差し替える場合（電源OFF修正版）:
cat a05ba-kernel/build/src/kernel/mediatek/mt8168/4.14/arch/arm64/boot/Image.gz \
    next_appended.dtb > /tmp/kernel_with_dtb
python3 kernel/pack-recovery.py /tmp/kernel_with_dtb \
    work/initramfs_alpine_v9.cpio.gz twrp/a05ba-tate.img work/linux_v10.img
```

焼き方:

```sh
# 方法A: Linux 稼働中に recovery パーティション (p15) へ直接書く（速い）
work/ssh.sh 'cat > /root/linux_v10.img' < work/linux_v10.img
work/ssh.sh 'dd if=/root/linux_v10.img of=/dev/mmcblk0p15 bs=1M; sync; rm /root/linux_v10.img'
bash boot_recovery.sh

# 方法B: fastboot 経由
adb reboot bootloader
fastboot flash recovery work/linux_v10.img
fastboot oem reboot-recovery
```

パーティション対応: `boot = mmcblk0p14` / **`recovery = mmcblk0p15`** / `cache = mmcblk0p31`

## Android に戻す

- `boot` (p14) は純正のまま。電源を切って普通に起動すれば Android が起動します。
- recovery を元に戻すには、各自が用意した純正 recovery イメージを
  `fastboot flash recovery <純正 recovery.img>` で書き戻してください。
- Android 側のカスタム ROM は本件とは独立で、本リポジトリでは扱いません。

## リポジトリに含まれないもの

リポジトリを軽量に保つため、巨大な純正ファームやカーネルクローンは**追跡していません**
（`.gitignore` 参照）。必要なら各自で入手してください。

| 除外物 | サイズ目安 | 入手先 |
| --- | --- | --- |
| `backup/`（実機パーティション吸い出し） | 165M | 各実機から TWRP で吸い出し（復旧用の控え） |
| `a05ba-kernel/` | 1.3G | https://github.com/coara-chocomaru/mt8168_a05ba_kernel |
| `mouseos-a05bd-kernel/`（Neo 用・参照） | 1.2G | https://github.com/mouseos/mt8168_a05bd_kernel |
| `mtkclient/` | 91M | https://github.com/bkerler/mtkclient |
| `twrp/*.img`（`a05ba-tate.img` 以外） | 各 16M | https://github.com/coara-chocomaru/TAB-A05-BA1-Next-TWRP |

## 現状 / 次の一手

- **達成**: 電源投入だけで Linux(GNOME) が起動（`para`=p16 の BCB を `ct-next-boot` が毎起動 `boot-recovery` にセット）。
  Android に戻すときは Linux 上で `ct-next-android`。
- **達成**: GNOME Flashback デスクトップ（gnome-panel + metacity）。オンスクリーンキーボード `onboard`、
  タッチ90°変換、バックライト消灯対策、hostname `ct-next`、英語UI＋TZ Asia/Tokyo、
  GNOME 設定の Users/Region 有効化まで確認済み。
- 未実施: 物理的な電源ボタン OFF→ON、タッチ回転方向の最終確定（`ct-next-touch`）、日本語UI（`-lang`）。
- **横表示は不可**: このカーネルは fbdev のみ。`fb0` の `var.rotate` は解像度を入れ替えるだけで走査は回らず、
  X の fbdev `Rotate` も破綻する（90°回転はディスプレイ HW/MTK disp 側が必要で fbdev からは不可）。縦で運用。
- **電源OFF**: 純正カーネルの `mt_power_off()`（`mtk_rtc_common.c` / `mt6358_misc.c`）は、**充電器(USB/AC)接続中は
  `arch_reset`＝再起動**する実装。そのため `kernel/ct-next-kernel.patch` でこの分岐を削除した**カスタムカーネル**を
  `kernel/build-kernel.sh` で作り、`kernel/pack-recovery.py` で recovery イメージに組み込んで使う。
  これにより充電器を挿したままでも `poweroff` で再起動せず電源断する（実機で確認）。
  （このセッションは手動起動で logind セッションが無いため `loginctl poweroff` は elogind に無視される。
  GNOME の電源メニューも systemd 依存で無効。代わりに `pkexec /usr/local/bin/ct-next-power {poweroff,reboot}`
  を使う Shutdown/Reboot ランチャーを同梱し、`ct-next-power.policy` でパスワード不要にしている）
- `boot` (p14) への転用は不可: boot スロットでは自作 initramfs（ramdisk）が実行されず Android が起動する（検証済み）。
- 別ディストロ: 永続化は SD 上に tarball 展開する方式。`init` の `tar xzf /alpine.tar.gz` を
  別 distro の tarball に差し替えれば入れ替え可能。

## ライセンス / 注意

個人の実験プロジェクトです。本リポジトリには**純正ファームウェアやベンダー由来のバイナリは含まれません**が、
`twrp/a05ba-tate.img` など第三者が配布するイメージを参照用に保持しています。これらは各配布元の
ライセンスに従ってください。作業はすべて自己責任で。

## 参考リンク

- Next カーネルソース: https://github.com/coara-chocomaru/mt8168_a05ba_kernel
- Next 用 TWRP: https://github.com/coara-chocomaru/TAB-A05-BA1-Next-TWRP
- 仕様 (Wiki): https://wiki3.jp/SmileTabLabo/page/14
