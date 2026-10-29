-- HD2-Lang: mods/alpha_f_bloodfallen/hud_lite
-- HUD Lite 简体中文补充包：当加载器语言选为「简体中文」时，菜单里的选项与分组标题显示中文。
-- 名称与官方 zh_cn 包一致，加载器会按 name 合并；英文环境不受影响。
-- 纯数据文件：只允许字面量、表、字符串。
return {
  name = '简体中文',
  code = 'zh-CN',
  text = {
    -- 分组标题
    ['DISPLAY'] = '显示',
    ['RING LAYOUT'] = '环布局',
    ['VITALS'] = '生命与耐力',
    ['AMMUNITION'] = '弹药',
    ['WEAPON ROW'] = '武器行',
    ['FIRE AND AMMO ICONS'] = '射击模式与弹种图标',
    ['ZEROING AND RPM'] = '归零与射速',
    ['RESERVES'] = '备弹',
    ['STIMS AND GRENADES'] = '针剂与手雷',
    ['SQUAD'] = '小队',
    ['ANIMATION'] = '动画',

    -- 显示
    ['HUD cluster'] = 'HUD 整体',
    ['Opacity (%)'] = '不透明度（%）',
    ['Scale'] = '缩放',
    ['Show when idle'] = '待机时显示',
    ['full brightness'] = '全亮',
    ['faint (30%)'] = '淡化（30%）',

    -- 环布局
    ['Offset X (px @1080p)'] = '水平偏移（像素 @1080p）',
    ['Offset Y from bottom (px @1080p)'] = '距底部偏移（像素 @1080p）',
    ['Outer ring radius (px @1080p)'] = '外环半径（像素 @1080p）',
    ['Inner ring radius (px @1080p)'] = '内环半径（像素 @1080p）',
    ['Outer ring thickness (px)'] = '外环粗细（像素）',
    ['Inner ring thickness (px)'] = '内环粗细（像素）',
    ['Arc span (degrees)'] = '弧线张角（度）',
    ['Arc tracks'] = '弧线底环',
    ['Ring smoothing (0 = off)'] = '环平滑（0 = 关闭）',
    ['Backpack ring (third right)'] = '背包环（右侧第三环）',
    ['Backpack offset X (px @1080p)'] = '背包水平偏移（像素 @1080p）',
    ['Backpack offset Y from bottom (px @1080p)'] = '背包距底部偏移（像素 @1080p）',
    ['Backpack ring radius (px @1080p)'] = '背包环半径（像素 @1080p）',
    ['Backpack ring thickness (px)'] = '背包环粗细（像素）',
    ['Backpack arc span (degrees)'] = '背包弧线张角（度）',

    -- 生命与耐力
    ['Health ring (outer left)'] = '生命环（左外）',
    ['Stamina ring (inner left)'] = '耐力环（左内）',
    ['Health and stamina row (armed and unarmed)'] = '生命与耐力行（持枪与空手）',
    ['Health and stamina text offset X (px)'] = '生命与耐力文字水平偏移（像素）',
    ['Health and stamina row offset Y (px, + is up)'] = '生命与耐力行垂直偏移（像素，+ 为上）',
    ['Health and stamina text height (px @1080p)'] = '生命与耐力文字高度（像素 @1080p）',

    -- 弹药
    ['Ammo ring (right)'] = '弹药环（右）',
    ['Centre number'] = '中央数字',
    ['Centre ammunition format'] = '中央弹药格式',
    ['rounds / capacity'] = '弹药 / 容量',
    ['rounds only'] = '仅弹药',
    ['Number alignment'] = '数字对齐',
    ['left'] = '左',
    ['centre'] = '居中',
    ['Number offset Y (px, + is up)'] = '数字垂直偏移（像素，+ 为上）',
    ['Centre number offset X (px)'] = '中央数字水平偏移（像素）',
    ['Centre number height (px @1080p)'] = '中央数字高度（像素 @1080p）',

    -- 武器行
    ['Unlock information row (individual positions)'] = '解锁信息行（单项位置）',
    ['Weapon icon position'] = '武器图标位置',
    ['crosshair'] = '准星',
    ['game HUD'] = '游戏 HUD',
    ['Information row offset X from approved origin'] = '信息行相对基准的水平偏移',
    ['Information row offset Y (px, + is up)'] = '信息行垂直偏移（像素，+ 为上）',
    ['Information row visible edge gap (px)'] = '信息行可见边缘间距（像素）',

    -- 射击模式与弹种图标
    ['Fire mode icon (independent)'] = '射击模式图标（独立）',
    ['Unlocked fire mode position X'] = '解锁后射击模式位置 X',
    ['Unlocked fire mode position Y'] = '解锁后射击模式位置 Y',
    ['Fire mode icon size'] = '射击模式图标大小',
    ['Ammo type / weapon function icon'] = '弹种 / 武器功能图标',
    ['Unlocked ammo type position X'] = '解锁后弹种位置 X',
    ['Unlocked ammo type position Y'] = '解锁后弹种位置 Y',
    ['Ammo type icon size'] = '弹种图标大小',

    -- 归零与射速
    ['Scope zeroing icon'] = '瞄具归零图标',
    ['Unlocked zeroing position X'] = '解锁后归零位置 X',
    ['Unlocked zeroing position Y'] = '解锁后归零位置 Y',
    ['Zeroing icon size'] = '归零图标大小',
    ['Rate of fire setting icon'] = '射速档位图标',
    ['Unlocked rate of fire position X'] = '解锁后射速位置 X',
    ['Unlocked rate of fire position Y'] = '解锁后射速位置 Y',
    ['Rate of fire icon size'] = '射速图标大小',

    -- 备弹
    ['Reserve / backpack numbers'] = '备弹 / 背包数字',
    ['Unlocked reserve count position X'] = '解锁后备弹数量位置 X',
    ['Unlocked reserve count position Y'] = '解锁后备弹数量位置 Y',
    ['Reserve magazine count text height'] = '备弹数量文字高度',
    ['Magazine icon beside reserve count'] = '备弹数量旁的弹匣图标',
    ['Reserve magazine icon size'] = '备弹弹匣图标大小',
    ['Magazine icon to count gap'] = '弹匣图标与数量的间距',

    -- 针剂与手雷
    ['Stim icon and quantity'] = '针剂图标与数量',
    ['Unlocked stim position X'] = '解锁后针剂位置 X',
    ['Unlocked stim position Y'] = '解锁后针剂位置 Y',
    ['Grenade icon and quantity'] = '手雷图标与数量',
    ['Unlocked grenade position X'] = '解锁后手雷位置 X',
    ['Unlocked grenade position Y'] = '解锁后手雷位置 Y',
    ['Consumable icon size'] = '消耗品图标大小',
    ['Consumable quantity text height'] = '消耗品数量文字高度',
    ['STIM '] = '针剂 ',
    ['GREN '] = '手雷 ',

    -- 小队
    ['Own booster icon'] = '自身增益图标',
    ['Squad boosters and death icons'] = '小队增益与死亡图标',

    -- 动画
    ['Reload progress'] = '换弹进度',
    ['Reload interpolation response (0 = raw samples)'] = '换弹插值响应（0 = 原始采样）',
  },
}
