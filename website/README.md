# 产品官网

GitHub Pages 地址：https://jesseovo.github.io/jiaxintie/

此目录是官网的可维护源码。首页保持简洁，详细内容分别来自 `docs/ABOUT.md` 与 `docs/usage.zh-CN.md`，构建后生成 About 和使用手册页面。

## 本地预览

先将 v1.0 Release 的两个 ZIP 和 `SHA256SUMS.txt` 下载到 `build-tools/release-v1.0/assets/`，然后执行：

```bash
python3 scripts/build-product-site.py --output build-tools/product-site
python3 -m http.server 4173 --directory build-tools/product-site
```

构建会核对安装包的 SHA-256，再复制到网站的 `downloads/`。二进制只用于网站构建输出，不重复提交到此 GitHub 仓库。

## GitHub Pages 发布

在仓库 **Settings → Pages → Build and deployment → Source** 选择 **GitHub Actions**。私有仓库需要支持私有 Pages 的 GitHub 付费套餐；免费套餐需使用公开仓库。

工作流位于 `.github/workflows/pages.yml`。向 `main` 提交官网、About、使用手册或构建脚本修改时会自动发布，也可在 Actions 中手动执行。工作流下载已发布的 v1.0 安装包，校验 SHA-256，构建并检查页面，再发布到 GitHub Pages。无需额外保存访问令牌。

页面资源与下载链接使用相对路径，适配 `/jiaxintie/` 子目录。构建脚本默认使用以上 Pages 地址，也可通过 `--public-url` 指定部署地址，用于生成 canonical、分享图片地址和 sitemap。

页面无外部字体或脚本依赖。仅在浏览器本地保存明暗模式偏好；演示不读取真实桌面、剪贴板或文件。
