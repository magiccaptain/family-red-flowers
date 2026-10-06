# 小花园 · 小红花成长记录

给家里小朋友记录努力和小心愿的 Flutter 应用。当前版本 **0.2.4** 支持 Android 手机、平板和 Linux 桌面，直接连接阿里云 PostgreSQL，共享同一个家庭的数据；本机使用 Linux 窗口调试。

## 已实现

- 添加和切换多位小朋友，设置昵称、动物头像和初始小红花数量。
- 修改孩子设置和当前花数；花数调整形成独立记录，历史保留。
- 奖励小红花并填写事由，数据库保存成功后播放花朵和彩纸动画。
- 兑换小红花，记录数量、事由、时间及兑换后的余额；余额不足无法兑换。
- 努力候选项默认是“英语打卡、单词打卡、体育打卡、早睡早起”；点击旁边的“设置”可新增、修改或删除。
- 心愿灵感默认只保留“看10分钟喜欢的动画”（5 朵）；点击“设置”可管理心愿名称和兑换花数。两组设置各支持最多 20 项，也可全部删除，随家庭数据跨设备同步，重启后保留。
- 成长记录按类型筛选，所有孩子、花数、奖励、兑换、调整记录和当前选择都保存到 PG。
- 前台每 30 秒同步，回到应用时同步，也可点击右上角手动同步。
- 多设备并发奖励会累加；并发兑换不会透支；保存响应丢失后使用原操作编号确认结果，避免重复记账。
- 断网时可查看上次同步的数据；新增奖励、兑换和设置需要联网确认。界面显示同步时间、离线或待确认状态。
- 首次连接可以导入该设备旧版的本地孩子和完整历史，保留原本地数据。重复导入跳过相同记录；发现本地、云端历史冲突时停止导入并保留原数据。

家庭专用 Android 安装包预置现有受限家庭账号，首次打开自动连接，无需填写或粘贴配置。首次使用不创建示例孩子或虚构记录。

## 本机运行

Linux 应用菜单已安装“小花园”入口，图标与 Android 一样是小红花。可以直接搜索“小花园”打开，或运行桌面版本：

```bash
./scripts/start-linux.sh
```

项目的数据库已经初始化，私有连接配置位于 `artifacts/pg-connection.json`。需要热重载调试时执行：

```bash
source ~/.zshenv
flutter pub get
./scripts/run-linux.sh
```

脚本通过环境变量指定配置文件路径，运行时读取配置；密码没有写入 Dart 源码或编译参数。终端按 `r` 热重载、`R` 热重启、`q` 退出。VS Code 提供 Linux 云端调试和 Android 调试配置。

直接连接 PG 使用原生 TCP，浏览器版无法使用这条连接。旧的 `run-web.sh`、`run-preview.sh` 保留在项目中，当前版本打开网页会提示使用 Android 或 Linux。

桌面打包版本也可以使用：解压 `artifacts/linux/red-flowers-v0.2.4-linux-x64.tar.gz`，运行 `bundle/red_flowers`，在首次连接页面粘贴同一份家庭配置。

Linux 窗口图标已内置到可执行文件；运行调试脚本也会更新当前用户的应用菜单和图标。若程序已经打开，退出后重新启动即可加载新窗口图标。

本机连接配置属于私密文件，包含此家庭的受限数据库账号；分享给自己的其他设备即可，不要公开上传。

## Android 手机和平板

最低支持 **Android 7.0 / API 24**，手机和平板使用同一个安装包，横屏、竖屏自适应。

手机窄屏使用紧凑的单列卡片，顶部保留同步和云端设置，小朋友设置可从花数卡片进入；奖励快捷按钮提供 48×48 的触摸区域。记录的数量、余额和时间自动换行，历史统计在窄屏分行排列。添加和兑换表单可滚动，键盘弹出后仍能滚动到提交按钮；奖励时收起键盘，长昵称和较大系统字体下也能完整显示动画。

1. 安装 `artifacts/android/red-flowers-v0.2.4-family.apk`。
2. 打开应用，自动连接当前家庭 PG 并同步数据，无需输入连接配置。旧版在该设备上的本地记录会自动迁移，原数据保留。
3. 其他家庭设备安装同一个 APK，即可共享孩子、花数和完整记录。

首次打开暂时断网时，点击“重试连接”即可；成功同步过的设备断网后仍可查看缓存。已保存过的设备连接设置优先于预置配置，右上角仍可修改连接设置。

家庭 APK 构建方式：`scripts/build-apk.sh` 从本机私有文件 `artifacts/pg-connection.json` 读取受限账号，通过临时 `--dart-define-from-file` 编译进应用，构建后清理临时文件；源码不写入真实密码。该 APK 仅供家庭内部使用。直接执行普通 `flutter build apk` 不会预置账号。

手动修改的连接配置使用设备安全存储保存，不放进普通数据缓存。

当前 PG 服务器尚未启用 TLS，生成的配置使用 `disable`，应用也会显示连接未加密。服务器启用 TLS 后，再更新各设备的连接加密设置；使用有效证书时选择“TLS，验证证书”。

USB 安装和调试：

```bash
./scripts/build-apk.sh
adb devices
adb install -r build/app/outputs/flutter-apk/app-release.apk
flutter devices
flutter run -d <平板设备ID>
```

当前 release 使用 Flutter 的开发签名，适合家庭试用安装；正式分发前需配置长期签名。后续更新需要保持同一签名和应用 ID `cn.familygarden.red_flowers`，才能继续读取旧版本地数据。

## 数据库初始化与结构

管理员连接信息仅放在本机 `.env` 文件，字段模板见 `.env.example`。若未指定数据库名，默认使用 `postgres`。

```bash
./scripts/init-database.sh
```

脚本创建 Python 虚拟环境、安装数据库驱动、建表和创建家庭应用账号，并生成私有连接配置。重复运行保留已有账号、孩子和历史，不清空数据。

数据库使用独立的 `red_flowers` schema：

| 表 | 保存内容 |
| --- | --- |
| `families` | 家庭与登录账号对应关系、当前孩子、数据版本、努力候选项、心愿灵感 |
| `children` | 孩子昵称、头像、花数、创建时间 |
| `flower_entries` | 初始花数、奖励、兑换、调整的完整流水 |
| `commands` | 操作编号和参数，防止重试重复记账 |
| `schema_versions` | 数据库结构版本 |

应用账号只允许调用 `get_garden()` 和 `apply_command(jsonb)`，不能直接改表、调用私有函数或访问其他家庭。数据库函数使用事务和家庭行锁，把花数与流水一起保存。家庭专用安装包内置该家庭的受限连接账号；管理员账号不进入客户端。

数据库结构版本 2 为已有家庭补充这两组默认设置，重复初始化保留已修改的候选项。设置更新使用独立命令和原设置校验；另一台设备同时修改同一组内容时会提示重新同步，避免覆盖新设置。旧客户端仍能记账，新设置需要使用 0.2.4 或更高版本。

服务器需要允许设备访问 PG 端口。当前开发机已验证可以连接；平板的实际网络连通性和真机安装仍需在设备上确认。

## 本机开发环境

| 工具 | 版本 / 路径 |
| --- | --- |
| Flutter stable | 3.47.6，`/home/sc/develop/flutter` |
| Dart | 3.13.5，包含在 Flutter SDK 中 |
| Java | OpenJDK 17，`/usr/lib/jvm/java-17-openjdk-amd64` |
| Android SDK | `/home/sc/Android/Sdk`，API 35 / 36、Platform Tools |
| Linux 工具链 | clang、CMake、Ninja、GTK 3、libsecret、jsoncpp 开发库 |
| Linux 安全存储 | 当前桌面的 Secret Service / KWallet |

Flutter、Java 和 Android 路径已配置在 `~/.zshenv`。未安装 Android Studio 或 Android 模拟器，本机窗口调试直接使用 Linux。

## 验证

```bash
flutter analyze
flutter test
./scripts/test-pg.sh
flutter build linux --release
./scripts/build-apk.sh
```

Flutter 测试覆盖原有记账和奖励动画、不同屏幕布局、云端连接表单、旧数据导入、离线缓存、重启恢复与重复请求确认。`test-pg.sh` 另外在真实 PG 上验证完整功能、两个客户端并发、事务回滚、账号权限和导入，再用实际 Dart PostgreSQL 驱动完成集成测试，包括编译预置账号后在没有设备配置的情况下自动连接并跨客户端同步。

数据库测试创建独立的临时家庭与账号，完成后清理自己的测试数据，不修改正式家庭的孩子和记录。普通 `flutter test` 跳过需要真实连接的集成测试，由 `test-pg.sh` 提供临时配置执行。

家庭预置版本已通过 38 项 Flutter 测试和 2 项真实 PG 驱动集成测试，静态检查无问题。数据库层此前已通过 9 项真实 PG 测试，Linux 窗口也已实际连接云端。Android 尚未真机安装验证。验证完毕后退出调试窗口并停止构建守护进程。

手机适配验证覆盖 320×640（1.5 倍文字）、360×800、393×852（1.3 倍文字）、412×915，以及 800×360 横屏，包含系统安全区域、键盘弹出、长昵称、六位花数和完整奖励／兑换操作。全部 45 项 Flutter 测试通过，静态检查无问题，Android 与 Linux 构建成功；APK 保留预置家庭账号，并与上一版使用相同签名。验证日志在 `artifacts/phone-layout-tests.txt`、`artifacts/phone-tests.txt`、`artifacts/phone-analyze.txt`；Android、Linux 构建日志在 `artifacts/phone-android-build.txt`、`artifacts/phone-linux-build.txt`。模拟界面截图保存在 `artifacts/screenshots/phone-*.png`，不使用正式家庭数据。

图标更新构建与静态检查日志在 `artifacts/icon-linux-build.txt`、`artifacts/icon-android-build.txt`、`artifacts/icon-analyze.txt`。

0.2.4 的设置功能已通过 51 项 Flutter 测试、11 项数据库测试和 2 项实际 Dart PG 驱动集成测试，静态检查无问题。覆盖候选项新增、修改、删除、取消、保存失败、旧缓存默认值、重启恢复、跨设备同步与冲突，以及 320 像素窄屏放大字体和键盘弹出后的编辑与兑换。日志在 `artifacts/suggestions-tests.txt`、`artifacts/suggestions-widget-tests.txt`、`artifacts/suggestions-pg-tests.txt`、`artifacts/suggestions-analyze.txt`。设置页面截图在 `artifacts/screenshots/phone-*-reward-settings.png` 和 `artifacts/screenshots/phone-*-wish-settings.png`，使用测试数据。

0.2.4 Android 和 Linux release 均构建成功；Android 包版本号为 6，与 0.2.3 家庭包签名相同，可以覆盖安装。构建日志在 `artifacts/suggestions-android-build.txt`、`artifacts/suggestions-linux-build.txt`，签名检查和 SHA-256 在 `artifacts/suggestions-build-verification.txt`。当前 Linux 启动入口使用更新后的本机构建，重新打开应用即可看到设置入口。

两端图标构建检查通过：Linux 实际启动成功，嵌入的窗口图标与共享图稿一致；Android 五种密度图标及自适应资源均已打包。新版保留家庭预置账号，与上一版签名一致，可以覆盖安装。

家庭预置版本验证日志在 `artifacts/family-tests.txt`、`artifacts/family-analyze.txt`、`artifacts/family-pg-integration.txt`，安装包构建日志在 `artifacts/family-android-build.txt`。此前数据库和桌面验证日志、旧版安装包及界面截图保留在 `artifacts/`。

## 主要代码

- `database/schema.sql`：表结构、权限边界、事务记账、旧数据导入。
- `database/initialize.py`：数据库初始化、生成受限家庭账号和本机私有配置。
- `lib/data/pg_gateway_native.dart`：原生 PG 连接、参数化命令、连接超时和错误处理。
- `assets/icon.svg`：Android 和 Linux 共用的小红花图标源文件。
- `scripts/generate-icons.py`：生成两端的位图及 Android 自适应图标；需要 `librsvg2-bin`（本机已安装）。
- `scripts/install-linux-launcher.py`：安装当前用户的 Linux 应用菜单入口与图标。
- `scripts/build_family_apk.py`：从私有配置构建家庭专用 APK。
- `lib/data/pg_preset.dart`：读取编译时的受限家庭账号。
- `lib/data/pg_repository.dart`：云端读取、设备连接配置、缓存、迁移、待确认操作恢复。
- `lib/data/garden_store.dart`：业务校验，确认云端保存后更新余额和记录。
- `lib/ui/pg_connection.dart`：连接设置、粘贴配置和设备间分享。
- `lib/ui/garden_screen.dart`：花园、心愿兑换、成长记录、同步状态。
- `lib/ui/dialogs.dart`：孩子设置、努力候选项和心愿灵感设置、兑换表单。
- `lib/ui/illustrations.dart`：头像、花朵和奖励动画。

旧版本地数据键 `red_flowers_garden_v1` 保留作为迁移来源。云端缓存和待确认请求按家庭分别保存；手动连接设置保存于安全存储，家庭 APK 的默认受限账号编译进应用。数据库时间使用 UTC，界面转换为设备本地时间。

字体为 Noto Sans CJK SC，许可说明见 `assets/fonts/LICENSE.txt`。
