# 第三方声明

[English](THIRD_PARTY_NOTICES.md) · [中文文档索引](docs/INDEX.zh-CN.md)

**HUD Lite 1.0.2** 由 **Alpha F. Bloodfallen** 维护。
该署名表示 HUD Lite 自身的工作，不代表拥有第三方贡献的原创权。

## NarrowHUD 兼容数据

**Based on NarrowHUD by luka189（基于 luka189 的 NarrowHUD）**。
核对版本：https://github.com/luka189/NarrowHUD/releases/tag/v1.0.6

`config/weapon_catalog.json` 的兼容目录来自该项目的网络类型、字段资料和随包观察数据。
HUD Lite 保留自己的绘制，通过 `src/compatibility.lua` 与 `src/runtime.lua` 接入；
没有移植其运行模块、布局编辑器或美术。

完整许可见 [third_party/COMPATIBILITY-LICENSE.txt](third_party/COMPATIBILITY-LICENSE.txt)。
许可允许免费使用和修改，要求保留署名及许可，禁止售卖或付费墙分发相关作品及派生内容；
其中允许捐赠和模组站点奖励计划。含该目录的分发包须遵守这些条件，MIT 许可不会覆盖它们。
不能将所使用的兼容数据宣称为完全独立原创。

其他游戏派生数据仍适用下文权利说明。

## 图形署名

用户提供的 `cura.svg` 针剂图标及 `Grenade_Currency_Icon.svg` 手雷图标署名为
**Traced by Dogo314**。原路径和 viewBox 保持不变，描述元数据集中至本文件。
附件及素材哈希见 `third_party/CONSUMABLE-ICONS-SOURCE.json`；这些本地输入不代表额外
获得超出适用图形／游戏内容条款的分发权利。

数量符号以及图标/贴图资源包来自 Helldivers 2 社区 wiki，署名 **Dogo314**。
应保留该署名并确认相应分发权限。资源包位于 `assets/icon-pack/`，
随仓库一同分发，但不进入源码导出。
用户提供的图像和其他图形内容，仍受各自权利人的条款约束。

## 游戏内容

游戏派生内容属于 Arrowhead Game Studios 及相应权利人，
不因 HUD Lite 使用 MIT 许可证而获得新的授权，也不包含在公开源码导出中。

## 加载器与开发依赖

- **Chef Shared Loader**，作者 Th3chef，需要单独安装：
  https://github.com/Th3chef/Chef-Shared-Loader
- **@resvg/resvg-js**：MPL-2.0，通过包管理器安装。
- **luaparse**：MIT，通过包管理器安装。
- **Pillow**、**lupa**：单独安装，适用各自许可证。

源码导出不内置加载器或上述依赖的实现代码。
