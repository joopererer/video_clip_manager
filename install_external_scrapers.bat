@echo off
chcp 65001 >nul
echo ========================================
echo 外部 Scraper 依赖安装脚本
echo ========================================
echo.

echo 正在检查 Python 安装...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Python 未安装，请先安装 Python 3.7+
    echo 下载地址: https://www.python.org/downloads/
    pause
    exit /b 1
)
echo ✅ Python 已安装

echo.
echo 正在检查 pip...
pip --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ pip 未安装，请先安装 pip
    pause
    exit /b 1
)
echo ✅ pip 已安装

echo.
echo 正在安装外部 scraper 依赖...

echo.
echo 1. 安装 javscraper...
pip install javscraper
if %errorlevel% neq 0 (
    echo ❌ javscraper 安装失败
) else (
    echo ✅ javscraper 安装成功
)

echo.
echo 2. 安装 requests...
pip install requests
if %errorlevel% neq 0 (
    echo ❌ requests 安装失败
) else (
    echo ✅ requests 安装成功
)

echo.
echo 3. 安装 beautifulsoup4...
pip install beautifulsoup4
if %errorlevel% neq 0 (
    echo ❌ beautifulsoup4 安装失败
) else (
    echo ✅ beautifulsoup4 安装成功
)

echo.
echo 4. 安装 lxml...
pip install lxml
if %errorlevel% neq 0 (
    echo ❌ lxml 安装失败
) else (
    echo ✅ lxml 安装成功
)

echo.
echo 5. 安装 tmdbv3api...
pip install tmdbv3api
if %errorlevel% neq 0 (
    echo ❌ tmdbv3api 安装失败
) else (
    echo ✅ tmdbv3api 安装成功
)

echo.
echo 6. 检查 yt-dlp...
yt-dlp --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ⚠️  yt-dlp 未安装，请手动安装
    echo 安装命令: pip install yt-dlp
) else (
    echo ✅ yt-dlp 已安装
)

echo.
echo ========================================
echo 安装完成！
echo ========================================
echo.
echo 可用的外部 scraper:
echo - yt-dlp: 通用视频下载器
echo - jav-scraper: JAV 内容信息获取
echo - TMDB API: 电影信息获取
echo.
echo 注意: 使用 TMDB API 需要配置 API Key
echo 获取地址: https://www.themoviedb.org/settings/api
echo.
pause
