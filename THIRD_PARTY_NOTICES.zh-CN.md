# 第三方声明

[English](THIRD_PARTY_NOTICES.md) · [中文文档索引](docs/INDEX.zh-CN.md)

**HUD Lite 1.0.0** 由 **Alpha F. Bloodfallen** 维护。
该署名表示 HUD Lite 自身的工作，不代表拥有第三方贡献的原创权。

## 独立性说明

HUD Lite 的实现、绘制代码和构建工具均为本次发布独立编写。
同游戏的其他 HUD 模组只在功能范围与界面惯例上提供了参考，不属于本代码库的一部分，
也不对其实现主张或要求署名。跨模组共用的游戏派生数据（对象哈希、字段名、图标索引）
记录在 `config/` 中，属于下文所述的游戏内容。

## 图形署名

数量符号以及本地构建使用的图标/贴图资源包来自 Helldivers 2 社区 wiki，
署名 **Dogo314**。应保留该署名并确认相应分发权限。
提取出的资源包位于 `assets/icon-pack/`，属于本地构建输入，不包含在公开源码导出中。
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
