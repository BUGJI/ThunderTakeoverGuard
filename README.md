# Thunder Takeover Guard

一个用于**解除迅雷（Thunder/Xunlei）对已注册浏览器 HTTP 下载的无差别接管**的 Windows 脚本工具。

迅雷会安装 `XLServicePlatform` 服务、`XLWFP` / `XLGuard` 内核驱动，以及 Chrome/Edge 外部扩展和 Native Messaging Host，用于拦截浏览器的普通 HTTP 下载。本工具通过停止/禁用相关组件、清理浏览器扩展注册表项来解除这种接管。

> **先读风险提示，再决定是否使用。** 本工具存在已知蓝屏风险，因为其涉及内核驱动层操作，详见下文。

---

## 文件说明

| 文件 | 作用 |
|---|---|
| `start.cmd` | 中文交互菜单启动器，双击即可使用 |
| `ThunderTakeoverGuard.ps1` | 主脚本，实际执行所有操作 |

两个文件需放在**同一目录**下。`start.cmd` 会自动定位同目录的 `.ps1`。

---

## 快速开始

1. 将两个文件放到同一文件夹。
2. 双击 `start.cmd`，出现菜单：

   ```
   [1] 仅预览 DryRun（不改任何东西）
   [2] 立即应用 Apply（停/禁用服务与驱动）
   [3] 应用并安装登录任务 InstallTask
   [4] 查看状态 Status
   [5] 移除登录任务 RemoveTask
   [0] 退出
   ```

3. **第一次使用请先选 `[1]` 预览**，确认脚本将要做的改动，再决定是否执行 `[2]` 或 `[3]`。
4. 执行 `[2]` / `[3]` 会触发 UAC 提权，需管理员权限。

也可以绕过菜单，直接带参数调用（兼容原命令行用法）：

```bat
start.cmd -DryRun
start.cmd -Status
start.cmd -Apply -KeepFiles
```

---

## 参数说明（直接调用 PowerShell 时）

| 参数 | 作用 |
|---|---|
| `-DryRun` | 只预览，不做任何修改 |
| `-Apply` | 立即应用加固 |
| `-Status` | 显示当前服务/驱动/文件/扩展/任务状态 |
| `-InstallTask` | 应用并注册登录时自动重跑的计划任务 |
| `-RemoveTask` | 移除该计划任务 |
| `-DeleteServices` | 额外删除服务/驱动的注册表键（更强，迅雷可能重建） |
| `-KeepFiles` | 不重命名服务/插件/驱动二进制文件 |
| `-RemoveBHO` | 额外移除 IE 的 XunleiBHO 注册 |
| `-RemoveAgentCom` | 额外移除 ThunderAgent COM 注册 |
| `-NoElevate` | 不自动提权（计划任务和只读测试用） |
| `-Quiet` | 只写日志，不输出到控制台 |

菜单里的 `[A]–[E]` 对应上表中的附加参数。

---

## 它具体做了什么

- 停止并禁用 `XLServicePlatform` 服务、`XLWFP` / `XLGuard` 驱动
- 重命名正在使用的服务/插件/驱动二进制（加 `.thunder-guard-disabled` 后缀，可逆；被占用时安排重启后重命名）
- 删除 Chrome / Edge 中迅雷相关的外部扩展注册表项和 Native Messaging Host
- 删除浏览器用户数据目录下的迅雷扩展文件夹
- 可选：移除 IE BHO、ThunderAgent COM 注册
- 可选：安装登录计划任务，每次登录后自动重新应用

所有注册表删除前都会导出备份到：

```
%ProgramData%\ThunderTakeoverGuard\backup-<时间戳>\
```

日志位于：

```
%ProgramData%\ThunderTakeoverGuard\guard.log
```

---

## ⚠️ 风险提示（重要）

**1. 蓝屏风险 —— 主要来自内核驱动操作**

`XLWFP.sys` 和 `XLGuard.sys` 是已知会导致蓝屏的驱动，多个 Microsoft Q&A 案例中社区专家的建议是卸载迅雷或删除这两个驱动文件。

本脚本在 `-Apply` 模式下会对这两个驱动执行 `sc stop` / `sc config start=disabled`，并在文件被占用时安排重启后重命名。**在一个已经因驱动问题而不稳定的系统上，这种操作会显著增加触发蓝屏或系统无法正常启动的概率。**

如果你只想解除浏览器接管、不想碰内核驱动，请使用：

```bat
start.cmd -Apply -KeepFiles
```

或在菜单 `[2]` 之后选 `[D] -KeepFiles`。这样只清理浏览器扩展和用户态组件，不动 `.sys` 驱动文件。注意 `-KeepFiles` 不阻止 `sc stop`/`sc config`，如需完全避开驱动操作，建议手动处理或修改脚本。

**2. 可逆性有限**

文件重命名和注册表删除在脚本层面是可逆的（有备份），但迅雷客户端在下次启动时可能**重新写入**扩展注册表项、重建服务。计划任务的作用就是在每次登录后重新清理。

**3. 可能违反迅雷用户协议**

迅雷协议禁止对软件进行反向工程、修改或删除相关组件。本工具通过系统工具禁用其核心组件，可能被迅雷视为违反协议的行为。请自行评估合规风险。

**4. 不是官方方案**

迅雷客户端内存在“接管设置 / 浏览器支持”选项，部分版本可以取消勾选“接管所有浏览器”。如果你的版本有这个开关，**优先使用官方开关**，本工具仅作为开关失效或不存在时的备选。

---

## 建议的使用顺序

1. 先检查迅雷客户端内是否有“接管浏览器下载”开关，有则优先关闭。
2. 用 `start.cmd -Status` 查看当前状态。
3. 用 `start.cmd -DryRun` 预览改动。
4. 如需解除接管但想避开驱动风险，用 `start.cmd -Apply -KeepFiles`。
5. 确认效果稳定后，再考虑 `-InstallTask` 防止迅雷重建。
6. 如需彻底移除迅雷组件，优先考虑通过控制面板**卸载迅雷**，而非脚本强删驱动。

---

## 卸载 / 恢复

- 移除计划任务：菜单 `[5]` 或 `start.cmd -RemoveTask`
- 恢复被重命名的文件：手动把 `.thunder-guard-disabled` 后缀去掉（重启后操作更稳妥）
- 恢复注册表：从 `%ProgramData%\ThunderTakeoverGuard\backup-*\` 导入对应 `.reg` 文件
- 最彻底的恢复方式仍是**卸载并重装迅雷**（如果你还需要它）

---

## 免责声明

本工具按“现状”提供，不附带任何担保。使用前请自行备份重要数据，并在理解上述风险的前提下操作。因使用本工具导致的系统不稳定、蓝屏、数据丢失或与迅雷的协议纠纷，由使用者自行承担。
