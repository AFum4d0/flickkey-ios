param([int]$Start = 0, [int]$Count = 200, [int]$KeyDelay = 4)
# Google 日本語入力に AJIMEE-Bench の問題を打たせ、変換キー 1 回 + 確定 の結果を集める。
# 自前の入力欄に前の文を入れておき、その後ろでローマ字を 1 キーずつ送る。
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class K {
  [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(32)] public long pad; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int size);
  [DllImport("user32.dll")] static extern short VkKeyScan(char c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("imm32.dll")] public static extern IntPtr ImmGetContext(IntPtr h);
  [DllImport("imm32.dll")] public static extern bool ImmSetOpenStatus(IntPtr c, bool o);
  [DllImport("imm32.dll")] public static extern bool ImmGetOpenStatus(IntPtr c);
  [DllImport("imm32.dll")] public static extern bool ImmSetConversionStatus(IntPtr c, int a, int b);
  [DllImport("imm32.dll")] public static extern bool ImmReleaseContext(IntPtr h, IntPtr c);
  static void Send(ushort vk, bool up) {
    var i = new IN[1]; i[0].type = 1; i[0].ki.vk = vk; i[0].ki.flags = up ? 2u : 0u;
    SendInput(1, i, Marshal.SizeOf(typeof(IN)));
  }
  public static void Key(ushort vk) { Send(vk, false); Send(vk, true); }
  public static void Char(char c) {
    short s = VkKeyScan(c); ushort vk = (ushort)(s & 0xFF); bool shift = (s & 0x100) != 0;
    if (shift) Send(0x10, false);
    Key(vk);
    if (shift) Send(0x10, true);
  }
}
"@
$items = Get-Content "$PSScriptRoot\gime_items.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$form = New-Object Windows.Forms.Form
$form.Text = "AJIMEE 測定中（触らないでください）"; $form.Width = 900; $form.Height = 160; $form.TopMost = $true
$tb = New-Object Windows.Forms.TextBox
$tb.Dock = "Fill"; $tb.Multiline = $true; $tb.Font = New-Object Drawing.Font("Yu Gothic UI", 12)
$form.Controls.Add($tb)
$form.Show(); [Windows.Forms.Application]::DoEvents()

function Pump([int]$ms) { $t = [DateTime]::Now.AddMilliseconds($ms); while ([DateTime]::Now -lt $t) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 5 } }
function Focus-Ime {
  [K]::SetForegroundWindow($form.Handle) | Out-Null; $form.Activate(); $tb.Focus() | Out-Null; Pump 100
  $c = [K]::ImmGetContext($tb.Handle)
  [K]::ImmSetOpenStatus($c, $true) | Out-Null
  [K]::ImmSetConversionStatus($c, 0x9, 0) | Out-Null  # ひらがな（NATIVE | FULLSHAPE）
  [K]::ImmReleaseContext($tb.Handle, $c) | Out-Null
  Pump 100
}

$out = @()
foreach ($it in ($items | Select-Object -Skip $Start -First $Count)) {
  Focus-Ime
  $tb.Text = $it.ctx; $tb.SelectionStart = $tb.Text.Length; Pump 50
  foreach ($ch in $it.romaji.ToCharArray()) { [K]::Char($ch); Pump $KeyDelay }
  Pump 150
  Write-Host ("typed=[{0}] fg={1}" -f $tb.Text, ([K]::GetForegroundWindow() -eq $form.Handle))
  [K]::Key(0x20); Pump 400   # 変換
  [K]::Key(0x0D); Pump 200   # 確定
  $text = $tb.Text
  $res = if ($text.StartsWith($it.ctx)) { $text.Substring($it.ctx.Length) } else { $text }
  $out += [pscustomobject]@{ i = $it.i; output = $res; ok = ($it.answers -contains $res) }
  Write-Host ("{0} {1} {2}" -f $it.i, ($it.answers -contains $res), $res)
}
$form.Close()
$out | ConvertTo-Json -Depth 3 | Out-File "$PSScriptRoot\gime_out_$Start.json" -Encoding utf8
