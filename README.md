# MyBooks Koreader 插件

MyBooks 的 KOReader 客户端插件，用于在电子书阅读器上浏览书架、同步阅读进度和标注。

## 构建

```bash
make
```

生成 `dist/mybooks_koplugin_<version>.zip`，版本号取自 [mybooks.koplugin/_meta.lua](mybooks.koplugin/_meta.lua)。

清理构建产物：

```bash
make clean
```

## 安装

将压缩包解压后得到的 `mybooks.koplugin` 目录复制到 KOReader 的 `plugins` 目录，重启 KOReader 即可：

```
koreader/
└── plugins/
    └── mybooks.koplugin/
```

## 目录结构

```
mybooks.koplugin/
├── _meta.lua        # 插件元信息（名称、版本）
├── main.lua         # 插件入口
├── mybooks_*.lua    # 各功能模块
├── icons/           # 图标资源
└── ui/              # 通用 UI 组件
```

## 许可证

[MIT](LICENSE)
