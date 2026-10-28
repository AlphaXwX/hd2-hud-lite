# HUD Lite

**1.0.2 · Alpha F. Bloodfallen**

[English](README.md) · [中文文档索引](docs/INDEX.zh-CN.md)

面向《绝地潜兵2》（Helldivers 2）的游戏内 HUD 模组。需要单独安装
**Chef Shared Loader 1.2.3 或更新版本**。

## 功能

- 针剂和手雷使用提供的独立图标显示数量，空手时同样可见。
- 背包资源显示在右侧第三环，不占用左侧生命／耐力环。
- 新武器缺少换弹映射时，通过已声明的换弹阶段读取真实角色动画；不使用固定计时。
- 纯冷却及不可换弹武器隐藏备用弹匣，保留实际已装填弹药；可换弹武器仍显示真实零备弹。
- 多人识别不受无关对象增减干扰；主机持有的本地装备必须具备 owner 匹配依据。

本次构建补充了已验证的背包供弹关系、其他已知握持姿态武器类型及字段调用名兼容。
没有姿态依据的武器仍保持未识别状态，不猜测当前手持对象。

- 持枪与空手时均显示 HP 和耐力。
- 显示弹药、弹匣容量、备用弹药及受支持的背包计量。
- 右内环显示能量充能，右外环显示冷却就绪度。
- 由动画采样驱动的平滑白色换弹环。
- 独立显示射击模式、弹种设置、归零和射速图标。
- 默认按针剂、手雷、归零、弹种、射速、弹匣数量、射击模式固定顺序补位；仅确认支持时显示归零。
- 开启信息行解锁后，各项独立定位，不再动态补位。
- 背包环使用相同的 Ring layout 控件，设置按十一个可搜索分类连续排列。
- 显示本人及最多三名队友的增益和死亡图标。
- 备用弹药数量旁显示弹匣符号，可单独调整尺寸和间距。
- 使用作者调校的 1080p 默认布局，支持分辨率缩放和 F9 调节。
- 已保存的个人设置优先于发布版默认值。

## 安装

1. 安装 **Chef Shared Loader 1.2.3+**。
2. 停用本模组的重复安装，以及存在冲突的其他 HUD 模组。
3. 在模组管理器导入并部署 `HUD-Lite-1.0.2-Chef.zip`。
4. 按 **F9** 打开 Chef 菜单，进入 **HUD Lite 1.0.2**。

加载标识、性能页名称和原生调用保护见[加载标识说明](docs/IDENTITY.zh-CN.md)。
需要重新部署并重启游戏；游戏中已经加载的模组不能原地更改性能页 ID。

不要为了强制执行已被拒绝的引擎读取而删除 Chef 的安全状态文件。

## 配置

F9 菜单可调整圆环几何参数、文字位置、透明度、独立设置图标、备弹数字与
弹匣符号、小队增益显示及动画平滑。

位置和尺寸采用 **1920×1080 设计坐标**，会随其他分辨率等比缩放，
不会改变游戏本身的显示分辨率。

数据通道不可用或数据过期时，会隐藏依赖该数据的显示，不用虚构数值代替。
真实空弹匣和零备弹仍属于有效数据，正常显示。

## 构建与测试

需要 **Python 3.11+** 与 **Node.js 20+**。构建不需要下载任何输入；
重建图标包的方法见[构建指南](docs/BUILD.zh-CN.md)。

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
npm ci
.venv\Scripts\python tools/build.py --source-only
.venv\Scripts\python tests/verify.py
.venv\Scripts\python tests/verify_icon_assets.py
.venv\Scripts\python tests/benchmark.py
.venv\Scripts\python tests/verify_release.py
.venv\Scripts\python tests/verify_docs.py
.venv\Scripts\python tools/build.py
.venv\Scripts\python tests/verify.py dist/HUD-Lite-1.0.2-Chef.zip
.venv\Scripts\python tests/verify_release.py dist/HUD-Lite-1.0.2-Chef.zip
```

Linux、macOS 请将解释器路径替换为 `.venv/bin/python`。
不要提交 `local.config.json`。

## 项目结构

| 路径 | 用途 |
|---|---|
| `project.json` | 产品名称、版本、作者及管理器描述 |
| `src/` | 主循环、原生读取、配置和绘制模块 |
| `tools/` | 本地导入、组装、检查和打包工具 |
| `tests/` | Lua 功能回归、图像、安装包和文档检查 |
| `config/` | 发布视觉预设及已验证的字段、图标映射 |
| `docs/` | 英文和简体中文说明 |
| `external/` | 可选本地资源包的导入目录，不提交 |
| `assets/` | 图标包、数量符号和预览图，随源码一同分发 |
| `build/` | 不提交的生成代码、补丁文件和管理器元信息 |
| `reports/` | 不提交的测试、耗时和校验报告 |
| `dist/` | 不提交的安装包和源码包 |

## 源码导出

```powershell
.venv\Scripts\python tools/check_repository.py
.venv\Scripts\python tools/export_source.py
```

源码 ZIP 使用明确的文件白名单，不包含本地输入、图像、生成代码、游戏派生内容、
依赖安装目录、个人路径、本地设置和测试日志。
工具不会自动上传 GitHub、执行 `git push` 或发布 Release。

## 验证范围与安全

- 测试使用真实 Lua 5.1 解释器和模拟游戏引擎。
- 模拟耗时**不等于游戏帧率，也不代表真实原生调用耗时**。
- 本次发布没有进行新的游戏内验证。
- 原生引擎调用仍可能导致崩溃；Lua `pcall` 无法隔离原生访问异常。
- 引擎读取按受控频率采样，绘制插值不会额外读取原生数据。
- 当前加载标识为 `mods/alpha_f_bloodfallen/hud_lite`，Chef 性能页显示 **hud_lite**。
  已保存的玩家数值优先于发布版默认值，详见[加载标识说明](docs/IDENTITY.zh-CN.md)。
- 不使用 FFI、任意内存访问，也不修改游戏数据文件。

## 许可与声明

HUD Lite 自行实现的代码及构建工具适用 [英文许可证](LICENSE)。
[中文译文](LICENSE.zh-CN.md) 仅供理解，英文原文为准。
其他包含或本地导入的内容保留各自条款；必要署名和分发边界集中在
[第三方声明中文版](THIRD_PARTY_NOTICES.zh-CN.md)。
