# 在线视频功能设置说明

## 概述
本应用支持从多个在线视频平台添加视频，包括：
- YouTube
- Bilibili
- MissAV
- XVideos

## 依赖安装

### 1. 安装 Python 依赖
运行以下命令安装必要的 Python 包：

```bash
# 安装 requests (HTTP 请求库)
pip install requests>=2.31.0

# 安装 bilibili-api (B站API库)
pip install bilibili-api>=16.1.0

# 安装 yt-dlp (视频下载工具)
pip install yt-dlp
```

或者直接运行安装脚本：
```bash
install_dependencies.bat
```

### 2. 安装 FFmpeg (可选)
如果需要视频处理功能，请安装 FFmpeg：
- 下载地址：https://ffmpeg.org/download.html
- 将 FFmpeg 添加到系统 PATH

## 功能说明

### 支持的平台

#### YouTube
- ✅ 支持视频信息提取
- ✅ 支持内嵌播放
- ✅ 支持流媒体播放
- ✅ 支持封面截图

#### Bilibili
- ✅ 支持视频信息提取
- ✅ 支持内嵌播放
- ✅ 支持封面截图
- ⚠️ 需要 Python 和 bilibili-api

#### MissAV
- ✅ 支持视频信息提取 (需要绕过 Cloudflare)
- ✅ 支持内嵌播放
- ⚠️ 可能遇到反爬虫限制

#### XVideos
- ✅ 支持视频信息提取 (需要绕过 Cloudflare)
- ✅ 支持内嵌播放
- ⚠️ 可能遇到反爬虫限制

### 常见问题

#### 1. Cloudflare 反爬虫错误
如果遇到 "HTTP Error 403 caused by Cloudflare anti-bot challenge" 错误：

**解决方案：**
- 确保已安装最新版本的 yt-dlp
- 使用模拟浏览器参数：`--extractor-args "generic:impersonate"`
- 禁用 cookies：`--no-cookies`（避免 Chrome cookie 数据库复制问题）
- 强制使用通用提取器：`--extractor generic --force-generic-extractor`
- 如果 yt-dlp 失败，系统会自动使用网页解析作为备用方案
- 如果网页解析也失败，系统会提供基于URL的基本信息
- 添加了完整的浏览器请求头模拟，包括 Sec-Fetch 系列头部

#### 2. Bilibili 提取失败
如果 Bilibili 视频信息提取失败：

**解决方案：**
- 确保已安装 `bilibili-api` 库
- 检查网络连接
- 确保视频 URL 格式正确
- 如果遇到编码错误或数据类型错误，系统会自动使用 yt-dlp 作为备用方案
- 设置环境变量：`set PYTHONIOENCODING=utf-8`
- 系统已修复数据类型转换问题（double 到 int 的转换）

#### 3. 视频信息不完整
如果视频缺少封面或时长信息：

**解决方案：**
- 检查网络连接
- 尝试重新添加视频
- 某些平台可能限制信息访问
- 系统已改进缩略图加载机制，添加了请求头和重试机制
- YouTube 缩略图使用 maxresdefault.jpg 格式
- Bilibili 缩略图会尝试多个 CDN 节点

### 使用说明

1. **添加在线视频**
   - 在 Videos 标签页点击 "Add Videos"
   - 选择 "Add Online Video"
   - 输入视频 URL
   - 系统会自动检测平台并提取信息

2. **播放在线视频**
   - 点击视频缩略图开始播放
   - 支持内嵌播放和流媒体播放
   - 可以使用播放控制功能

3. **创建片段**
   - 在线视频支持创建片段
   - 可以设置开始和结束时间
   - 支持标签和评分功能

## 技术架构

### 平台支持架构
```
PlatformFactory
├── YouTubeSupport
├── BilibiliSupport
├── MissAVSupport
└── XVideosSupport
```

### 播放器架构
```
UnifiedVideoPlayer
├── LocalPlayer (media_kit)
├── EmbeddedPlayer (WebView)
└── ExternalPlayer (stream)
```

### 数据流
```
URL → PlatformDetection → InfoExtraction → VideoInfo → OnlineVideo → UI
```

## 故障排除

### 检查依赖
```bash
# 检查 yt-dlp
yt-dlp --version

# 检查 Python
python --version

# 检查 bilibili-api
python -c "import bilibili_api; print('OK')"
```

### 日志查看
应用会在控制台输出详细的错误信息，包括：
- 平台检测结果
- 信息提取过程
- 错误详情

### 网络问题
- 确保网络连接正常
- 某些平台可能需要代理访问
- 检查防火墙设置

## 更新日志

### v1.0.1
- ✅ 添加在线视频基础架构
- ✅ 支持多平台视频添加
- ✅ 实现统一播放器
- ✅ 添加 Cloudflare 绕过支持
- ✅ 改进错误处理机制
