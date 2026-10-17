param([string]$Action='capture', [string]$Text='', [int]$X=0, [int]$Y=0, [string]$Output='figma-ui.png')
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class RainLinkDesktop {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION U; }
 [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public MOUSEINPUT mi; }
 [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk,wScan; public uint dwFlags,time; public UIntPtr dwExtraInfo; }
 [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx,dy; public uint mouseData,dwFlags,time; public UIntPtr dwExtraInfo; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool attach);
 [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetLastActivePopup(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 [DllImport("user32.dll")] public static extern void keybd_event(byte v,byte s,uint f,UIntPtr e);
 [DllImport("user32.dll")] public static extern uint SendInput(uint n,INPUT[] i,int s);
 public static void Text(string t) {
  foreach(char c in t) {
   INPUT[] i=new INPUT[2];
   i[0].type=1; i[0].U.ki.wScan=c; i[0].U.ki.dwFlags=4;
   i[1].type=1; i[1].U.ki.wScan=c; i[1].U.ki.dwFlags=6;
   SendInput(2,i,Marshal.SizeOf(typeof(INPUT)));
  }
 }
}
'@
$rainProcess=Get-Process -Name Figma | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (!$rainProcess) { throw 'Figma window not found' }
[RainLinkDesktop]::SetProcessDPIAware() | Out-Null
$rainPopup=[RainLinkDesktop]::GetLastActivePopup($rainProcess.MainWindowHandle)
if ($rainPopup -ne [IntPtr]::Zero -and [RainLinkDesktop]::IsWindowVisible($rainPopup)) {
 [RainLinkDesktop]::SetForegroundWindow($rainPopup) | Out-Null
} else {
 [RainLinkDesktop]::SetForegroundWindow($rainProcess.MainWindowHandle) | Out-Null
}
Start-Sleep -Milliseconds 200
$rainForeground=[RainLinkDesktop]::GetForegroundWindow()
[uint32]$rainForegroundPid=0
$rainForegroundThread=[RainLinkDesktop]::GetWindowThreadProcessId($rainForeground,[ref]$rainForegroundPid)
if ($rainForegroundPid -ne $rainProcess.Id) {
 $rainOwnThread=[RainLinkDesktop]::GetCurrentThreadId()
 [RainLinkDesktop]::AttachThreadInput($rainOwnThread,$rainForegroundThread,$true) | Out-Null
 try {
  [RainLinkDesktop]::BringWindowToTop($rainProcess.MainWindowHandle) | Out-Null
  [RainLinkDesktop]::SetForegroundWindow($rainProcess.MainWindowHandle) | Out-Null
 } finally { [RainLinkDesktop]::AttachThreadInput($rainOwnThread,$rainForegroundThread,$false) | Out-Null }
 Start-Sleep -Milliseconds 300
 [RainLinkDesktop]::GetWindowThreadProcessId([RainLinkDesktop]::GetForegroundWindow(),[ref]$rainForegroundPid) | Out-Null
}
if ($rainForegroundPid -ne $rainProcess.Id) { throw 'Figma did not receive focus; no input sent.' }
$rainRect=New-Object RainLinkDesktop+RECT
[RainLinkDesktop]::GetWindowRect($rainProcess.MainWindowHandle,[ref]$rainRect) | Out-Null
function Invoke-RainClick([int]$rainX,[int]$rainY) {
 [RainLinkDesktop]::SetCursorPos($rainRect.L+$rainX,$rainRect.T+$rainY) | Out-Null
 [RainLinkDesktop]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 70
 [RainLinkDesktop]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
}
switch ($Action) {
 'actions' { [RainLinkDesktop]::keybd_event(27,0,0,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(27,0,2,[UIntPtr]::Zero); Invoke-RainClick 45 85; Start-Sleep -Milliseconds 500; Invoke-RainClick 130 137; Start-Sleep -Milliseconds 1000 }
 'recent' { [RainLinkDesktop]::keybd_event(27,0,0,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(27,0,2,[UIntPtr]::Zero); Invoke-RainClick 45 85; Start-Sleep -Milliseconds 500; Invoke-RainClick 130 137; Start-Sleep -Milliseconds 1000; Invoke-RainClick 880 $Y; Start-Sleep -Milliseconds 1800 }
 'click' { [RainLinkDesktop]::SetCursorPos($rainRect.L+$X,$rainRect.T+$Y) | Out-Null; [RainLinkDesktop]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 70; [RainLinkDesktop]::mouse_event(4,0,0,0,[UIntPtr]::Zero) }
 'quick' { [RainLinkDesktop]::keybd_event(17,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100; [RainLinkDesktop]::keybd_event(191,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100; [RainLinkDesktop]::keybd_event(191,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100; [RainLinkDesktop]::keybd_event(17,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 1000 }
 'text' { [RainLinkDesktop]::Text($Text) }
 'enter' { [RainLinkDesktop]::keybd_event(13,0,0,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(13,0,2,[UIntPtr]::Zero) }
 'escape' { [RainLinkDesktop]::keybd_event(27,0,0,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(27,0,2,[UIntPtr]::Zero) }
 'lastplugin' { [RainLinkDesktop]::keybd_event(17,0,0,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(18,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100; [RainLinkDesktop]::keybd_event(80,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 100; [RainLinkDesktop]::keybd_event(80,0,2,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(18,0,2,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(17,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 1500 }
 'selectall' { [RainLinkDesktop]::keybd_event(17,0,0,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(65,0,0,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(65,0,2,[UIntPtr]::Zero); [RainLinkDesktop]::keybd_event(17,0,2,[UIntPtr]::Zero) }
}
Start-Sleep -Milliseconds 350
$rainShot=New-Object System.Drawing.Bitmap(($rainRect.R-$rainRect.L),($rainRect.B-$rainRect.T))
$rainGraphics=[System.Drawing.Graphics]::FromImage($rainShot)
$rainGraphics.CopyFromScreen($rainRect.L,$rainRect.T,0,0,$rainShot.Size)
$rainShot.Save((Join-Path $PSScriptRoot ('exports\home-controls-v7.1\'+$Output)))
$rainGraphics.Dispose(); $rainShot.Dispose()
Write-Output $Output
