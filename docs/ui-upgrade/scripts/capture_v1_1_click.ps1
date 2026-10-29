# Coordinate-driven capture of the real Windows build for the v1.1.0 release prep.
#
# The Flutter window does not expose its semantics tree to UI Automation in this
# environment, so this script drives the app like a user (click + type) and saves
# screenshots. Text-level assertions live in the widget tests instead.
#
# Usage:
#   $env:VCM_V11_DB = 'C:\path\db.json'
#   $env:VCM_V11_GRID = '1'
#   powershell -ExecutionPolicy Bypass -File docs\ui-upgrade\scripts\capture_v1_1_click.ps1
param(
  [string]$Exe = 'build\windows\x64\runner\Debug\video_clip_manager.exe',
  [string]$OutDir = 'docs\ui-upgrade\screenshots\v1_1_windows',
  [int]$StartupWaitSeconds = 20
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class VcmClick {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-Rect([IntPtr]$Hwnd) {
  $r = New-Object VcmClick+RECT
  [void][VcmClick]::GetWindowRect($Hwnd, [ref]$r)
  return $r
}

function Save-Shot([IntPtr]$Hwnd, [string]$Path) {
  $r = Get-Rect $Hwnd
  $w = $r.Right - $r.Left
  $h = $r.Bottom - $r.Top
  if ($w -le 0 -or $h -le 0) { return }
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}

function Click-At([IntPtr]$Hwnd, [double]$LogicalX, [double]$LogicalY) {
  $r = Get-Rect $Hwnd
  $scale = ($r.Right - $r.Left) / 1280.0
  $x = [int]($r.Left + $LogicalX * $scale)
  $y = [int]($r.Top + $LogicalY * $scale)
  [void][VcmClick]::SetCursorPos($x, $y)
  Start-Sleep -Milliseconds 200
  [VcmClick]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)  # left down
  Start-Sleep -Milliseconds 60
  [VcmClick]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)  # left up
  Start-Sleep -Milliseconds 400
}

$exePath = (Resolve-Path $Exe).Path
Write-Host "launching $exePath"
$proc = Start-Process -FilePath $exePath -PassThru
try {
  $deadline = (Get-Date).AddSeconds($StartupWaitSeconds)
  $hwnd = [IntPtr]::Zero
  while ((Get-Date) -lt $deadline -and $hwnd -eq [IntPtr]::Zero) {
    Start-Sleep -Milliseconds 500
    $hwnd = [VcmClick]::FindWindow('FLUTTER_RUNNER_WIN32_WINDOW', 'video_clip_manager')
  }
  if ($hwnd -eq [IntPtr]::Zero) { throw 'main window never appeared' }

  [void][VcmClick]::SetForegroundWindow($hwnd)
  Start-Sleep -Seconds 6
  Save-Shot $hwnd (Join-Path $OutDir '01_main_semantic_results.png')
  Write-Host 'captured main window'

  # Sidebar is 208 logical px wide; the header search box starts right after the
  # page title inside the content area.
  Click-At $hwnd 320 31
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait('snow')
  Start-Sleep -Seconds 2
  Save-Shot $hwnd (Join-Path $OutDir '02_keyword_hint.png')
  Write-Host 'captured keyword hint state'

  # Right-most header action is the About (info) button.
  Click-At $hwnd 1262 31
  Start-Sleep -Seconds 3
  Save-Shot $hwnd (Join-Path $OutDir '03_about_dialog.png')
  Write-Host 'captured about dialog'

  # Extract the icon the EXE actually ships, for the icon audit.
  $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
  if ($icon) {
    $icon.ToBitmap().Save((Join-Path $OutDir '04_exe_icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("exe icon: {0}x{1}" -f $icon.Width, $icon.Height)
  }

  [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
  Start-Sleep -Milliseconds 800
  Save-Shot $hwnd (Join-Path $OutDir '05_after_escape.png')
}
finally {
  if ($proc -and -not $proc.HasExited) {
    Start-Sleep -Milliseconds 500
    $proc.CloseMainWindow() | Out-Null
    Start-Sleep -Seconds 1
    if (-not $proc.HasExited) { $proc.Kill() }
  }
}
Write-Host 'done'
