# 产品官网

线上地址：https://jiaxintie.exactlake28.chatgpt.site/

此目录是官网的可维护源码。首页保持简洁，详细内容分别来自 `docs/ABOUT.md` 与 `docs/usage.zh-CN.md`，构建后生成 About 和使用手册页面。

## 本地预览

先将 v1.0 Release 的两个 ZIP 和 `SHA256SUMS.txt` 下载到 `build-tools/release-v1.0/assets/`，然后执行：

```bash
python3 scripts/build-product-site.py --output build-tools/product-site
python3 -m http.server 4173 --directory build-tools/product-site
```

构建会核对安装包的 SHA-256，再复制到网站的 `downloads/`。二进制只用于网站构建输出，不重复提交到此 GitHub 仓库。

## Sites 发布

- 项目 ID：`appgprj_6ae9933bc6cc81919915b0e46d09a4c5`
- 静态目录：`dist`
- 访问范围：公开产品官网。GitHub 源码仓库保持私有。

发布使用 Sites 的源码同步和归档流程；临时写入凭据仅通过 stdin 传给官方辅助脚本，不保存到源码或文件。修改后先构建、检查手机与桌面布局，再同步同一份源码、保存版本并部署。

页面无外部字体或脚本依赖。仅在浏览器本地保存明暗模式偏好；演示不读取真实桌面、剪贴板或文件。
