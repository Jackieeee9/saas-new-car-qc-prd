# SaaS 新车直销业务质检功能 · 需求框架与高保真原型

> 版本 **V2.12** ｜ 2026-11-13 ｜ 需求分析阶段

在线预览：**https://jackieeee9.github.io/saas-new-car-qc-prd/**

## 这是什么

SaaS 新车直销业务支持 AI 质检功能的需求文档与可交互高保真原型。页面包含两部分形态，右上角可随时切换：

- **原型预览**：左侧为公司质检系统（`qc.saas-direct.com`）的高保真界面模拟，覆盖质检中心、系统配置、规则配置、审批中心等 20 个页面；右侧同步展示当前模块的业务逻辑、查询条件、导出规则、交互说明与边界处理。
- **文档模式**：结构化的 PRD 正文，含需求修订记录、需求概览、产品设计、功能详情、规则与约束等章节，支持富文本编辑。

## 覆盖的模块

| 分组 | 页面 |
| --- | --- |
| 质检中心 | 质检工作台、微信质检、通话质检、视频质检、短信质检、质检记录、手动转单记录、质检案例库 |
| 系统配置 | 规则配置、审批中心、绑定关系配置 |

微信 / 通话 / 视频 / 短信四条质检链路均包含「列表 → 详情 → 人工复检」完整流程，并包含订单详情、转单等衍生页面。

## 本地运行

```bash
git clone https://github.com/Jackieeee9/saas-new-car-qc-prd.git
cd saas-new-car-qc-prd
python3 -m http.server 8899
# 打开 http://127.0.0.1:8899/
```

必须通过 HTTP 访问，直接双击 `index.html` 会因浏览器对本地文件的限制导致部分脚本行为异常。

## 目录结构

```
.
├── index.html                 # 原型单页（约 4.7 MB，样式/脚本/图片内联）
├── _shared/js/echarts.min.js  # 图表依赖（ECharts 5.5.1）
├── .nojekyll                  # 关闭 Jekyll，保证 _shared 下划线目录被正常发布
├── release.sh                 # 一键发版脚本
├── scripts/update_readme.py   # 发版时更新本文件的版本号与版本记录
└── notes/                     # 每个版本的发版说明（Release 正文来源）
```

`.nojekyll` 不是可选项：GitHub Pages 默认用 Jekyll 构建，会忽略以下划线开头的目录，缺失该文件时 `_shared/js/echarts.min.js` 将 404。

## 网络与代理

国内网络访问 `github.com` 经常超时（`api.github.com` 通常可达，`github.com:443` 会被卡）。git 与 curl 都读同一组环境变量，配一次即可：

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export NO_PROXY=localhost,127.0.0.1,::1,.local   # 本地服务不走代理
```

**端口必须和你本机代理客户端一致**，7890 只是 Clash 的默认值：

| 客户端 | 常见端口 |
| --- | --- |
| Clash / ClashX / Clash Verge | 7890（混合）、7897（Verge 默认） |
| Surge | 6152 |
| V2RayU / v2rayN | 1087（HTTP）、1080（SOCKS） |
| sing-box | 2080 |
| Shadowsocks | 1080 |

先确认代理真的在跑，再导变量——否则 git/curl 会连一个不存在的端口，报错反而更迷惑：

```bash
lsof -nP -iTCP:7890 -sTCP:LISTEN            # 有输出 = 端口在监听
curl -x http://127.0.0.1:7890 -I https://github.com   # 能拿到 200/301 = 代理可用
```

**三种配置层级，按需选：**

```bash
# 1) 只对这一次发版生效（脚本会同时给 git 和 curl 设置）
./release.sh <新html> --notes notes/v2.12.md --proxy http://127.0.0.1:7890

# 2) 只在当前终端窗口生效
export HTTPS_PROXY=http://127.0.0.1:7890

# 3) 只让 git 走代理（不影响其他命令，最不容易误伤）
git config --global http.https://github.com.proxy http://127.0.0.1:7890
git config --global --unset http.https://github.com.proxy   # 取消
```

开启代理后，`127.0.0.1:8899` 这类本地预览**不要**走代理，这也是 `NO_PROXY` 里要写 `localhost,127.0.0.1` 的原因。

**没有代理也能推**：`ssh.github.com:443` 通常不受影响（`github.com:22` 也常常通），可以改用 SSH 推送：

```bash
ssh -T -p 443 git@ssh.github.com          # 返回 "Hi <you>!" 即通
git remote set-url origin git@github.com:Jackieeee9/saas-new-car-qc-prd.git
```

此时推送走 SSH，而 Release、Pages 轮询走 `api.github.com`（一般可达），两条链路互不影响。

## 发版流程

拿到新导出的原型 HTML 后，一条命令完成「替换 → 提交 → 打 tag → 推送 → 发 Release → 等 Pages 构建 → 线上验收」：

```bash
./release.sh "../../【V2.12-查看】SaaS新车直销业务质检功能prd_2026-11-20.html" \
             --notes notes/v2.12.md
```

版本号默认从文件名里的 `V2.12` 识别，也可以 `--version v2.12.1` 指定，或 `--bump` 在当前 tag 上自增。

脚本会依次做：

1. 校验输入文件（大小、HTML 结构、是否与线上一致）
2. 覆盖 `index.html`，按 `--notes` 更新本文件顶部的版本号和「版本记录」表格
3. 提交、打 `v2.12.0` 标签、推送 `main` 和 tag
4. 调 API 创建 Release，并把 HTML 作为附件上传（方便离线传阅）
5. 轮询 Pages 构建，构建完成后访问线上地址，校验首页 200 与 echarts 200

**首次使用**需要存一次 token（存进 macOS Keychain，不落盘、不进仓库）：

```bash
./release.sh --save-token
```

Token 用 fine-grained PAT 即可，只需本仓库的 `Contents: Read and write`、`Releases: Read and write`、`Pages: Read`。

**常用参数**

| 参数 | 作用 |
| --- | --- |
| `--notes <file>` | 变更说明，同时用于 Release 正文和版本记录摘要 |
| `--version vX.Y.Z` | 显式指定版本号 |
| `--bump` | 在最新 tag 上 minor +1 |
| `--check <file>` | 只做校验，不改任何东西 |
| `--push-only` | 只把本地提交推上去 |
| `--resume` | 推送失败后接着跑，跳过提交步骤 |
| `--no-asset` | 不把 HTML 传为 Release 附件 |

**遇到问题**

- `连不上 api.github.com`：脚本会在改动前退出，仓库保持原样；配好代理后重试（`export HTTPS_PROXY=http://127.0.0.1:7890`）
- `已存在 tag`：说明该版本发过，换版本号，或 `git tag -d v2.12.0` 后再来
- 推送中断：本地提交和 tag 已经生成，直接 `./release.sh --resume`

## 版本记录

| 版本 | 日期 | 主要变更 |
| --- | --- | --- |
| V2.12 | 2026-11-13 | **质检案例库**：详情弹窗页面，每个质检任务类型均增加沟通记录展示。微信、通话、视频、短信四类案例分别展示对应的沟通记录（文字消息 / 语音通话 / 视频沟通 / 短信），与各任务详情页口径保持一致。 |
| V2.11 | 2026-10-23 | 质检工作台删除「客户姓名」列；微信质检详情删除「客户微信昵称」、新增「客户微信号」，「微信号」更名为「中台工作微信号」；通话质检详情「工作手机号」改为「中台手机号」、「被呼号码」改为「客户手机号」并删除「通话来源」；视频质检详情删除「视频类型」；短信质检详情「工作手机号」改为「中台手机号」；手动转单记录新增「任务编号」查询；质检案例库详情删除「客户姓名」；项目时间配置移除「启用状态」控件 |
| V2.10 | 2026-09-24 | 绑定关系配置调整「微信类型」下拉；质检记录中「最后一次沟通时间」更名为「创单时间」；规则配置项目时间页调整项目名称与审批状态操作 |

更早的修订明细见页面内「需求修订记录」章节。

## 说明

本仓库内容为公司内部产品需求文档，仅用于需求评审与研发对齐，未经许可请勿转载或对外分发。
