"""Native Windows verification helper (Python, Pillow, FFmpeg).

Generate synthetic media with `fixture`, build the Flutter fixture entry point,
then `launch`. All screenshots capture only the actual app's client area.
The fixture launcher uses in-memory preferences and an isolated sample database.
"""
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import ImageGrab

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "docs/ui-upgrade/logs/stage2"
STATE = LOGS / "capture-session.json"
OUT = ROOT / "docs/ui-upgrade/screenshots/stage2/windows"
USER = ctypes.windll.user32
USER.SetProcessDPIAware()
USER.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int,
                            ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_uint]
USER.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
USER.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]


def fixture():
    folder = Path(tempfile.mkdtemp(prefix="vcm-stage2-desktop-"))
    thumbs = folder / "Thumbnails"
    thumbs.mkdir()
    videos = []
    for index, size in enumerate(["640x360", "360x640"]):
        source = folder / f"sample_{index}_测试素材.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size={size}:rate=10", "-t", "6", "-c:v",
                        "libx264", "-pix_fmt", "yuv420p", str(source)], check=True)
        video_id = f"sample_video_{index}"
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(source), "-frames:v",
                        "1", str(thumbs / f"{video_id}.jpg")], check=True)
        videos.append(dict(id=video_id, path=str(source), name=source.name,
                           duration=6000, thumbnailPath=f"{video_id}.jpg"))
    clips = []
    names = ["示例 · 横屏色彩测试", "示例 · 竖屏构图测试", "示例 · 毫秒范围",
             "示例 · 长标签与 Unicode 文件名", "示例 · 收藏镜头", "示例 · 源文件缺失"]
    for index, name in enumerate(names):
        clip_id = f"sample_clip_{index}"
        video = videos[index % 2]
        (thumbs / f"{clip_id}.jpg").write_bytes((thumbs / video["thumbnailPath"]).read_bytes())
        clips.append(dict(id=clip_id, name=name,
                          videoPath=video["path"] if index < 5 else str(folder / "missing.mp4"),
                          start=125, end=3125 + index * 100, coverFrameTime=125,
                          tags=["示例素材", "竖屏" if index % 2 else "横屏",
                                "很长的标签用于验证窄屏截断与布局边界"],
                          notes="Synthetic FFmpeg test-pattern media for UI verification.",
                          rating=index % 5 + 1, isFavorite=index in (0, 3, 4),
                          thumbnailPath=f"{clip_id}.jpg"))
    clips[3]["tags"] = [clips[3]["tags"][2], "示例素材", "竖屏"]
    playlist = dict(id="sample_playlist", name="示例播放列表", description="仅用于阶段 2 UI 验证",
                    createdAt=1793000000000, updatedAt=1793000000000,
                    items=[dict(id=f"item_{i}", clipId=c["id"], order=i,
                                duration=c["end"]-c["start"]) for i, c in enumerate(clips[:3])])
    database = folder / "SAMPLE_UI_VERIFICATION.json"
    database.write_text(json.dumps(dict(clips=clips, videos=videos, playlists=[playlist],
                                       onlineVideos=[], onlineVideoClips=[]), ensure_ascii=False), encoding="utf-8")
    LOGS.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(dict(database=str(database))), encoding="utf-8")
    print(database)


def session():
    return json.loads(STATE.read_text(encoding="utf-8"))


def launch():
    data = session()
    env = dict(os.environ, VCM_STAGE2_DB=data["database"])
    log = open(LOGS / "windows-fixture-runtime.txt", "w", encoding="utf-8")
    process = subprocess.Popen([str(ROOT / "build/windows/x64/runner/Debug/video_clip_manager.exe")],
                               cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    handles = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    @callback_type
    def collect(handle, _):
        pid = wintypes.DWORD()
        USER.GetWindowThreadProcessId(handle, ctypes.byref(pid))
        if pid.value == process.pid and USER.IsWindowVisible(handle):
            handles.append(handle)
        return True

    for _ in range(30):
        USER.EnumWindows(collect, 0)
        if handles:
            break
        if process.poll() is not None:
            raise RuntimeError(f"App exited: {process.returncode}")
        time.sleep(0.5)
    if not handles:
        raise RuntimeError("No native app window appeared")
    data.update(pid=process.pid, hwnd=handles[0])
    STATE.write_text(json.dumps(data), encoding="utf-8")
    print(json.dumps(data))


def handle():
    data = session()
    window = data["hwnd"]
    pid = wintypes.DWORD()
    USER.GetWindowThreadProcessId(window, ctypes.byref(pid))
    if pid.value != data["pid"]:
        raise RuntimeError("The recorded fixture window is no longer active")
    USER.ShowWindow(window, 9)
    USER.SetForegroundWindow(window)
    return window


def capture(name, width, height):
    window = handle()
    client, outer = wintypes.RECT(), wintypes.RECT()
    USER.GetClientRect(window, ctypes.byref(client))
    USER.GetWindowRect(window, ctypes.byref(outer))
    USER.SetWindowPos(window, None, 50, 50,
                      width + outer.right - outer.left - client.right,
                      height + outer.bottom - outer.top - client.bottom, 0x0040)
    time.sleep(1)
    origin = wintypes.POINT()
    USER.ClientToScreen(window, ctypes.byref(origin))
    USER.GetClientRect(window, ctypes.byref(client))
    OUT.mkdir(parents=True, exist_ok=True)
    ImageGrab.grab(bbox=(origin.x, origin.y, origin.x+client.right, origin.y+client.bottom)).save(OUT / f"{name}.png")
    print(json.dumps(dict(image=name, width=client.right, height=client.bottom,
                          dpi=USER.GetDpiForWindow(window))))


def pointer(x, y, click):
    window = handle()
    origin = wintypes.POINT()
    USER.ClientToScreen(window, ctypes.byref(origin))
    USER.SetCursorPos(origin.x+x, origin.y+y)
    if click:
        USER.mouse_event(0x0002, 0, 0, 0, 0)
        USER.mouse_event(0x0004, 0, 0, 0, 0)
    time.sleep(0.4)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["fixture", "launch", "capture", "click", "hover", "keys", "close"])
    parser.add_argument("values", nargs="*")
    args = parser.parse_args()
    if args.action == "fixture":
        fixture()
    elif args.action == "launch":
        launch()
    elif args.action == "capture":
        capture(args.values[0], int(args.values[1]), int(args.values[2]))
    elif args.action in ("click", "hover"):
        pointer(int(args.values[0]), int(args.values[1]), args.action == "click")
    elif args.action == "keys":
        import win32com.client
        handle()
        win32com.client.Dispatch("WScript.Shell").SendKeys(args.values[0])
        time.sleep(0.5)
    elif args.action == "close":
        USER.PostMessageW(handle(), 0x0010, 0, 0)
