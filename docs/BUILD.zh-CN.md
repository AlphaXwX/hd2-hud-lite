# 构建指南

## 针剂和手雷图标输入

本地图形输入为 `assets/consumables/cura.svg` 和 `assets/consumables/grenade.svg`。
`tools/render_items.cjs` 构建时转为 512px 图像，再生成两个独立的 256px RGBA 原生纹理。
安装包包含 SVG／PNG，源码包沿用不包含图形输入的规则；重建前须另行提供本地素材。
图形署名及附件哈希集中在独立第三方文件中。

[English](BUILD.md) · [中文文档索引](INDEX.zh-CN.md)

## 前置条件

- Python 3.11 或更新版本，Node.js 20 或更新版本。
- 安装 `requirements-dev.txt` 中的 Python 依赖，以及锁文件中的 Node 依赖。
- 公开分发任何相关内容前，确认拥有相应分发权限。

## 构建输入

正常构建**不需要下载任何输入**，运行时、布局数据和图标包都在仓库里：

| 路径 | 内容 |
|---|---|
| `src/` | 组装成单个 Lua 模组的运行时模块 |
| `config/` | 布局、片段、映射和默认值数据 |
| `assets/icon-pack/` | 贴图、资源、数量符号和预览图 |

只有当你需要**从自己持有的资源包重建图标包**时，才需要本地输入：

| 配置键 | 构建用途 |
|---|---|
| `runtime_package` | 用于提取图标包的资源归档 |
| `icon_package` | 用于校验增益图标映射的图标定义 |
| `quantity_icon_svg` | 备用弹药数量旁的符号矢量图 |
| `preview_image` | 模组管理器中的预览图 |

```powershell
# 可选：把你持有的资源包导入已忽略的 external/ 目录。
Copy-Item local.config.example.json local.config.json   # 然后填写实际路径
.venv\Scripts\python tools/import_inputs.py --config local.config.json

# 从导入的归档重建图标包。
.venv\Scripts\python tools/extract_assets.py --package external/lite/<imported resource archive>
```

压缩包只会解压到已忽略的本地目录，导入器会拒绝越出目标目录的条目。
它不修改已安装的游戏文件、不访问游戏进程，也不上传任何内容。
不要提交 `local.config.json`。

## 构建流程

1. 从 `project.json` 读取显示元信息和 **1.0.3** 版本。
2. 图像准备阶段校验映射，并渲染备用数量符号。
3. 将 `src/` 模块、生成的布局数据和功能片段组装为 `build/hud_lite.lua`。
4. `tools/build.py --source-only` 生成原生补丁、预览图和管理器清单。
5. 按 README 中的命令执行 Lua、图像、耗时、发布包及文档检查。
6. `tools/build.py` 核对报告哈希，生成 `dist/HUD-Lite-1.0.3-Chef.zip`。
7. 对 ZIP 再运行 Lua 和发布检查，验证真正打入包内的内容。

管理器清单中的 `Version: 1` 表示**清单格式版本**，不是模组版本。
产品名称、Lua 模块和安装包文件名中的模组版本均为 **1.0.3**。

## 发布默认配置

`config/published_visual_defaults.json` 是已确认的 1920×1080 设计预设，
只影响选项注册时的默认值。构建不会捕获实时个人设置，启动时也不会重置已有配置。

## 预览图与图像处理

预览图会转为 RGBA PNG，不裁切、不叠加文字、不修改图像尺寸，
管理器使用包内的 `icon.png`。
备用数量符号在构建时转成位图，不在游戏运行时解析矢量图。

## 源码导出与 CI

```powershell
.venv\Scripts\python tools/check_repository.py
.venv\Scripts\python tests/verify_docs.py
.venv\Scripts\python tools/export_source.py
```

导出器只包含源码白名单以及中英文说明，排除生成输出、测试报告和依赖安装目录。
图标包随仓库分发，但不进入源码 ZIP；上传前请检查产出的归档内容。

CI 会执行仓库、文档与 Lua 检查，并用已提交的源码完整构建一次模组，
不会上传或公开安装包。
