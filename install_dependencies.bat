@echo off
chcp 65001 >nul
echo Installing Python dependencies for video_clip_manager...
echo.

echo Installing requests...
pip install requests>=2.31.0

echo Installing bilibili-api...
pip install bilibili-api>=16.1.0

echo Installing yt-dlp...
pip install yt-dlp

echo.
echo Setting up environment variables...
set PYTHONIOENCODING=utf-8

echo.
echo Dependencies installation completed!
echo Please make sure you have Python and pip installed.
pause
