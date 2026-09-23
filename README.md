# fe-base

前端基础课程上机作业与练习的静态站点，基于 [Jekyll](https://jekyllrb.com/) 与 [Chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) 主题搭建。

- 在线访问：<https://102300671.github.io/fe-base/>
- 作业源码带语法高亮与行号，HTML 作业支持页面内「源码 / 预览」一键切换

## 目录结构

```text
.
├── _config.yml            # 站点配置
├── _posts/                # 实验文章（每次实验一篇）
├── _tabs/                 # 导航页：分类 / 标签 / 归档 / 关于
├── _plugins/
│   └── include_source.rb  # 自定义标签：嵌入文件源码 + 在线预览
├── assets/
│   └── zip/lab1.zip       # 实验作业打包（zip），构建时随站点发布
├── labs/                  # 作业源文件，按实验次数组织
│   └── lab1/
│       ├── work1/
│       ├── work2/
│       └── ...
└── index.html
```

## 在文章中嵌入作业

使用自定义的 `include_source` 标签：

```liquid
{% include_source labs/lab1/work1/index.html %}
```

- HTML / HTM 文件默认显示高亮源码，并附带「预览」按钮（iframe 加载该文件的渲染结果，离开预览时自动重置）
- CSS / JS 等其他文件仅显示高亮源码

可选参数：

```liquid
{% include_source path/to/file.html preview %}    # 默认展示预览
{% include_source path/to/file.html nopreview %}  # 只显示源码，不显示预览
```

## 本地运行

```shell
bundle install
bundle exec jekyll serve
```

然后访问 <http://localhost:4000/fe-base/>。

## 许可

本站内容与代码基于 [MIT License](LICENSE) 发布，Jekyll 主题 Chirpy 同样采用 MIT 许可。
