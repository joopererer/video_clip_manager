# Drives the v1.1.0 Windows verification fixture with UI Automation and captures
# screenshots. Requires a debug/release build of
# test/fixtures/v1_1_desktop_fixture.dart and a sample database.
#
# Usage:
#   $env:VCM_V11_DB = 'C:\path\db.json'
#   $env:VCM_V11_GRID = '1'    # 1 = grid, 0 = list
#   powershell -ExecutionPolicy Bypass -File docs\ui-upgrade\scripts\capture_v1_1_windows.ps1
param(
  [string]$Exe = 'build\windows\x64\runner\Debug\video_clip_manager.exe',
  [string]$OutDir = 'docs\ui-upgrade\screenshots\v1_1_windows',
  [int]$StartupWaitSeconds = 12
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class VcmWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Dump-Tree {
  param($Root, [string]$LogPath, [int]$MaxDepth = 14)
  $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
  $lines = New-Object System.Collections.Generic.List[string]
  function Walk($node, $depth) {
    if ($null -eq $node -or $depth -gt $MaxDepth) { return }
    try {
      $name = $node.Current.Name
      $type = $node.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
      if ($name -or $type -eq 'Button' -or $type -eq 'Text' -or $type -eq 'Edit') {
        $lines.Add(("{0}{1} :: {2}" -f ('  ' * $depth), $type, $name))
      }
    } catch { }
    $child = $walker.GetFirstChild($node)
    while ($null -ne $child) {
      Walk $child ($depth + 1)
      $child = $walker.GetNextSibling($child)
    }
  }
  Walk $Root 0
  $lines | Set-Content -Path $LogPath -Encoding utf8
  return $lines
}

function Find-ByName {
  param($Root, [string]$Name)
  $cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
  return $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

function Find-Contains {
  param($Root, [string]$Needle)
  $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($el in $all) {
    try {
      if ($el.Current.Name -and $el.Current.Name.Contains($Needle)) { return $el }
    } catch { }
  }
  return $null
}

function Save-Shot {
  param([IntPtr]$Hwnd, [string]$Path)
  $rect = New-Object VcmWin+RECT
  [void][VcmWin]::GetWindowRect($Hwnd, [ref]$rect)
  $w = $rect.Right - $rect.Left
  $h = $rect.Bottom - $rect.Top
  if ($w -le 0 -or $h -le 0) { return }
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}

$exePath = (Resolve-Path $Exe).Path
Write-Host "launching $exePath"
$proc = Start-Process -FilePath $exePath -PassThru
try {
  $deadline = (Get-Date).AddSeconds($StartupWaitSeconds)
  $hwnd = [IntPtr]::Zero
  while ((Get-Date) -lt $deadline -and $hwnd -eq [IntPtr]::Zero) {
    Start-Sleep -Milliseconds 500
    $hwnd = [VcmWin]::FindWindow('FLUTTER_RUNNER_WIN32_WINDOW', 'video_clip_manager')
  }
  if ($hwnd -eq [IntPtr]::Zero) {
    $proc.Refresh()
    $hwnd = $proc.MainWindowHandle
  }
  if ($hwnd -eq [IntPtr]::Zero) { throw 'main window never appeared' }
  [void][VcmWin]::ShowWindow($hwnd, 3)  # maximize for a stable layout
  Start-Sleep -Seconds 2
  [void][VcmWin]::SetForegroundWindow($hwnd)
  Start-Sleep -Seconds 1

  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
  # Flutter's Windows embedder enables its accessibility bridge on demand and
  # fills the tree asynchronously, so give it a moment and poll for children.
  $lines = $null
  for ($i = 0; $i -lt 6; $i++) {
    Start-Sleep -Seconds 2
    $lines = Dump-Tree -Root $root -LogPath (Join-Path $OutDir '01_main_tree.txt')
    if ($lines.Count -gt 6) { break }
  }
  Write-Host ("semantic nodes: {0}" -f $lines.Count)
  Save-Shot -Hwnd $hwnd -Path (Join-Path $OutDir '01_main_window.png')

  $about = $null
  foreach ($needle in @('关于 Video Clip Manager', '关于')) {
    $about = Find-Contains -Root $root -Needle $needle
    if ($about) { break }
  }
  if ($about) {
    Write-Host 'clicking About'
    try {
      $about.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    } catch {
      $about.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    }
    Start-Sleep -Seconds 2
    $dialogRoot = [System.Windows.Automation.AutomationElement]::RootElement
    $dlg = Find-Contains -Root $dialogRoot -Needle 'Video Clip Manager'
    if ($dlg) {
      Dump-Tree -Root $dlg -LogPath (Join-Path $OutDir '02_about_tree.txt') | Out-Null
    }
    Save-Shot -Hwnd $hwnd -Path (Join-Path $OutDir '02_about.png')

    $check = Find-Contains -Root $dialogRoot -Needle '检查更新'
    if ($check) {
      Write-Host 'clicking 检查更新'
      try {
        $check.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
      } catch { Write-Host 'update button not invokable' }
      Start-Sleep -Seconds 12
      $dlg2 = Find-Contains -Root $dialogRoot -Needle 'Video Clip Manager'
      if ($dlg2) {
        Dump-Tree -Root $dlg2 -LogPath (Join-Path $OutDir '03_about_after_check.txt') | Out-Null
      }
      Save-Shot -Hwnd $hwnd -Path (Join-Path $OutDir '03_about_after_check.png')
    } else {
      Write-Host 'update button not found'
    }
    # close the dialog
    $close = Find-Contains -Root $dialogRoot -Needle '关闭'
    if ($close) {
      try { $close.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { }
    }
  } else {
    Write-Host 'about button not found'
  }
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
