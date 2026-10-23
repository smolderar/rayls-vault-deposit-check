$Host.UI.RawUI.WindowTitle = "Vault check"
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
Add-Type -AssemblyName System.Numerics
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RPC   = if ($env:VAULT_RPC) { $env:VAULT_RPC } else { "https://mainnet-rpc.rayls.com" }
$PAUSE = if ($env:VAULT_PAUSE) { [int]$env:VAULT_PAUSE } else { 8 }
$P     = "0x5b9565e27f5d50b14d3f660799f87e829a53fab2"   # launch-deposit contract
$TOKEN = "0xa069d3798feab32994ac5d98a9f011da6024f334"   # BRL1.p
$OPS   = "0x633ac5e2315b973417e8caa6b3ad2162e0461ce1"   # wallet that deployed and upgraded it
$SLOT  = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
$USERS = @("0x4d76d208692c1b1c22d77350b89396d76c947e22","0xc7e33057e72a5331e9ecbdd8159995de6c78f554",
           "0x93900b7a8e71e07dc053de5193fb3111ee888454","0x3d6c273cf204aac022810901e5cddb9c81f3b2b3",
           "0x9f939b630510d1d92ad7bdb40ce2348c31860603","0x4dee3358da4537a6b4428a551feb95c9a54c8fdc")
$ROLES = [ordered]@{
  "DEFAULT_ADMIN" = "0000000000000000000000000000000000000000000000000000000000000000"
  "UPGRADER"      = "189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3"
  "OPERATOR"      = "97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929"
  "PAUSER"        = "65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a"
}

$stamp  = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmm")
$report = Join-Path $PSScriptRoot "vault-report-v3-$stamp-UTC.txt"
$lines  = New-Object System.Collections.Generic.List[string]
function Out1($s) { Write-Host $s; [void]$lines.Add($s) }
function Screen($title) {
  if ($lines.Count -gt 0) { Start-Sleep -Seconds $PAUSE; Clear-Host }
  Out1 "Rayls vault launch deposits, read-only check   (all times UTC)"
  Out1 ""
  Out1 $title
}

$script:rid = 0
function Rpc($method, $params) {
  $script:rid++
  $body = '{"jsonrpc":"2.0","id":' + $script:rid + ',"method":"' + $method + '","params":' + $params + '}'
  try { $r = Invoke-RestMethod -Uri $RPC -Method Post -ContentType "application/json" -Body $body -TimeoutSec 30 }
  catch { return @{ err = "request failed" } }
  if ($r.error) { return @{ err = [string]$r.error.message } }
  if ($null -eq $r.result) { return @{ err = "no data" } }
  return @{ res = $r.result }
}
function CallTo($to, $data) { return Rpc "eth_call" ('[{"to":"' + $to + '","data":"' + $data + '"},"latest"]') }
function Call($data) { return CallTo $P $data }
function Pad($a) { return "000000000000000000000000" + ($a -replace '^0x','') }
function PadN($n) { return ([long]$n).ToString("x").PadLeft(64,'0') }
function Big($h) { $h = ([string]$h) -replace '^0x',''; if ($h -eq '') { return [System.Numerics.BigInteger]::Zero }
  return [System.Numerics.BigInteger]::Parse("0" + $h, [System.Globalization.NumberStyles]::AllowHexSpecifier) }
function Word($hex, $i) { $h = ([string]$hex) -replace '^0x',''; if ($h.Length -lt ($i+1)*64) { return "" }; return $h.Substring($i*64, 64) }
function Arg($data, $i) { return Word (([string]$data).Substring(10)) $i }
function Units($v) {
  $d = [System.Numerics.BigInteger]::Pow(10,18)
  $q = [System.Numerics.BigInteger]::Divide($v,$d); $r = [System.Numerics.BigInteger]::Remainder($v,$d)
  $s = $q.ToString("N0", [System.Globalization.CultureInfo]::InvariantCulture)
  if (-not $r.IsZero) { $f = $r.ToString().PadLeft(18,'0').Substring(0,2).TrimEnd('0'); if ($f) { $s = "$s.$f" } }
  return $s }
function Num($v) { return ([System.Numerics.BigInteger]$v).ToString("N0", [System.Globalization.CultureInfo]::InvariantCulture) }
function Utc($n) { return [DateTimeOffset]::FromUnixTimeSeconds([long]$n).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss") }
function Short($a) { return $a.Substring(0,6) + "..." + $a.Substring($a.Length-4) }
function Str($hex) {
  $len = [int](Big (Word $hex 1)); $h = (([string]$hex) -replace '^0x','').Substring(128, $len*2)
  $bytes = for ($i=0; $i -lt $h.Length; $i+=2) { [Convert]::ToByte($h.Substring($i,2),16) }
  return [Text.Encoding]::UTF8.GetString([byte[]]$bytes) }
function U($sel) { $r = Call $sel; if ($r.err) { return [System.Numerics.BigInteger]::MinusOne }; return Big $r.res }
$bt = @{}
function BlockTs($num) {
  if ($bt.ContainsKey($num)) { return $bt[$num] }
  $b = Rpc "eth_getBlockByNumber" ('["0x' + ([long]$num).ToString("x") + '",false]')
  $t = if ($b.err) { 0 } else { [long](Big $b.res.timestamp) }
  $bt[$num] = $t; return $t }
function Tx($hash) { return Rpc "eth_getTransactionByHash" ('["' + $hash + '"]') }

Write-Host ("=" * 88)
Write-Host "Vault check, read-only. Nothing is signed or sent."
Write-Host "1. Maximise this window."
Write-Host "2. Zoom with Ctrl + mouse wheel until the line of = signs above just fits on one line."
Write-Host "3. Start the screen recording, then press Enter."
[void](Read-Host)
Clear-Host

# Screen 1: cap history
Screen "1. Deposit cap, read from each setLimits transaction"
foreach ($h in @("0xa0e5e6ac3194a9418adc2598525b9cbc16c730776b0b855c45bd3fa274c0ec0c",
                 "0x7a37f9c2d8453eae5b19249015a09a5b9d608cdd1d13da0271742d62fbd270a8",
                 "0x255297246d318c789cd77260263fb63af118867f747994603d5d1a6b2c5c30cf")) {
  $t = Tx $h; if ($t.err) { Out1 "  $(Short $h)  could not read"; continue }
  $ts = BlockTs ([long](Big $t.res.blockNumber))
  Out1 ("  " + (Utc $ts) + "   total cap " + (Units (Big (Arg $t.res.input 2))).PadLeft(9) + "   per wallet " + (Units (Big (Arg $t.res.input 1))) + " BRL1.p")
}
$a = Tx "0x7a37f9c2d8453eae5b19249015a09a5b9d608cdd1d13da0271742d62fbd270a8"
$b = Tx "0x0c7c9d62d45208dc2504ee6547d84230e780c0f51ee899f557ca4f16b00e5620"
if (-not $a.err -and -not $b.err) {
  $t1 = BlockTs ([long](Big $a.res.blockNumber)); $t2 = BlockTs ([long](Big $b.res.blockNumber)); $sec = $t2 - $t1
  Out1 ""
  Out1 ("  250,000 cap set at " + (Utc $t1).Substring(11) + ", deposit that filled it at " + (Utc $t2).Substring(11))
  Out1 ("  -> filled in " + [math]::Floor($sec/60) + " min " + ($sec % 60) + " s")
}

# Screen 2: 19 Oct
Screen "2. The 19 Oct changes, read from each transaction"
$list = @("0xa8c2b0518f3e9ed5a426f1fe3051ddd7b425d8fa306ca7b9e9a2a130564c3279",
          "0x744f833b2e1e59430337c5c87ad1644db0f58d6a137eef9d9363f3bcef0e1377",
          "0x5199af7a8e3c91ef9383944dbb272cbe7c796acfae0efb2553524472b61a73f6",
          "0x9858393535b8eb3735cde29229e006486287b591095cb85866fa2d0d7e1d0700",
          "0xd9834b939d615b79dd57d0e40e44113ee1b744532dc3c49fbf91da0f6f04170e",
          "0x0027b90f20adf3ef49a4a0017617a380b50ffe3de7e8cc0ce65ff7053106f73a",
          "0x255297246d318c789cd77260263fb63af118867f747994603d5d1a6b2c5c30cf")
$createBlock = -1; $upgradeBlock = -2
foreach ($h in $list) {
  $t = Tx $h; if ($t.err) { Out1 "  $(Short $h)  could not read"; continue }
  $bn = [long](Big $t.res.blockNumber); $tm = (Utc (BlockTs $bn)).Substring(11)
  $in = [string]$t.res.input; $sel = if ($in.Length -ge 10) { $in.Substring(0,10) } else { "" }
  $from = Short ([string]$t.res.from)
  if (-not $t.res.to) { $what = "new contract created (code for the upgrade)"; $createBlock = $bn }
  elseif ($sel -eq "0x4f1ef286") { $what = "upgradeToAndCall -> code " + (Short ("0x" + (Arg $in 0).Substring(24))); $upgradeBlock = $bn }
  elseif ($sel -eq "0xf2eab735") { $what = "0xf2eab735(" + (Big (Arg $in 0)) + ")" }
  elseif ($sel -eq "0x58b257b0") { $what = "setWeek(week " + (Big (Arg $in 0)) + ", rate " + (Num (Big (Arg $in 3))) + ")" }
  elseif ($sel -eq "0x189ae5f2") { $what = "setLimits(total " + (Units (Big (Arg $in 2))) + ")" }
  else { $what = $sel }
  Out1 ("  block " + $bn + "  " + $tm + "  from " + $from + "  " + $what)
}
if ($createBlock -eq $upgradeBlock) { Out1 ""; Out1 "  -> new code created and switched on in the same block ($createBlock)" }

# Screen 3: state now
Screen "3. The contract now"
$impl = Rpc "eth_getStorageAt" ('["' + $P + '","' + $SLOT + '","latest"]')
$implA = if ($impl.err) { "error" } else { "0x" + (([string]$impl.res) -replace '^0x','').Substring(24) }
$v = Call "0xffa1ad74"; $ver = if ($v.err) { "error" } else { Str $v.res }
Out1 "  code in use     $implA"
Out1 "  VERSION()       $ver"
Out1 "  current week    $(U '0x06575c89') of $(U '0xdcd087a4')"
$rate1 = [System.Numerics.BigInteger]::Zero
for ($w=1; $w -le 4; $w++) {
  $r = Call ("0x1469971d" + (PadN $w)); if ($r.err) { continue }
  $rate = Big (Word $r.res 2); if ($w -eq 1) { $rate1 = $rate }
  Out1 ("  week $w          " + (Num $rate).PadLeft(5) + " RLS per 1,000 BRL1.p, deposits until " + (Utc (Big (Word $r.res 0))))
}
Out1 ("  limits          min " + (Units (U '0x41b3d185')) + ", per wallet " + (Units (U '0xbf613202')) + ", total " + (Units (U '0x648e3c26')) + " BRL1.p")
Out1 ("  deposited       " + (Units (U '0xff50abdc')) + " BRL1.p from " + (U '0x277e9d28') + " wallets")
$vr = Call "0xfbfa77cf"; $va = if ($vr.err) { "error" } else { "0x" + (([string]$vr.res) -replace '^0x','').Substring(24) }
if ($va -match '^0x0+$') { $va = "not set (0x000...000)" }
Out1 "  vault()         $va"
Out1 ("  lock ends       " + (Utc (U '0xa0ee4501')))

# Screen 4: keys
Screen "4. Who can change it"
foreach ($k in $ROLES.Keys) {
  $r = Call ("0x91d14854" + $ROLES[$k] + (Pad $OPS))
  $val = if ($r.err) { "error" } elseif ((Big $r.res).IsZero) { "no" } else { "yes" }
  Out1 ("  " + ($k + "_ROLE").PadRight(19) + " held by " + (Short $OPS) + " : " + $val)
}
$c = Rpc "eth_getCode" ('["' + $OPS + '","latest"]')
if (-not $c.err) { $n = [int](((([string]$c.res).Length) - 2) / 2)
  Out1 ""
  if ($n -eq 0) { Out1 "  code stored at $(Short $OPS): 0 bytes"; Out1 "  -> an ordinary wallet with one key, not a multisig contract" } else { Out1 "  code stored at $(Short $OPS): $n bytes" } }

# Screen 5: credited rewards
Screen "5. What each depositor was credited"
$sumW1 = [System.Numerics.BigInteger]::Zero; $sumRls = [System.Numerics.BigInteger]::Zero
foreach ($u in $USERS) {
  $g = Call ("0x6f77926b" + (Pad $u)); if ($g.err) { Out1 "  $(Short $u) error"; continue }
  $dep = Big (Word $g.res 0); $rls = Big (Word $g.res 4)
  $w1 = Call ("0x3166983a" + (Pad $u) + (PadN 1)); $w1v = if ($w1.err) { [System.Numerics.BigInteger]::Zero } else { Big $w1.res }
  $sumW1 += $w1v; $sumRls += $rls
  $per = if ($dep.IsZero) { "0" } else { Num ([System.Numerics.BigInteger]::Divide($rls * 1000, $dep)) }
  Out1 ("  " + (Short $u) + "  week-1 deposit " + (Units $w1v).PadLeft(9) + "   RLS " + (Units $rls).PadLeft(10) + "  = " + $per + " per 1,000")
}
$atNow = [System.Numerics.BigInteger]::Divide($sumW1 * $rate1, 1000)
Out1 ""
Out1 (("  week-1 deposits x week-1 rate today (" + (Num $rate1) + ")").PadRight(48) + ": " + (Units $atNow) + " RLS")
Out1 ("  RLS credited to the same wallets".PadRight(48) + ": " + (Units $sumRls) + " RLS")

# Screen 6: token
Screen "6. BRL1.p"
$ts = CallTo $TOKEN "0x18160ddd"; $bal = CallTo $TOKEN ("0x70a08231" + (Pad $P))
if (-not $ts.err) { Out1 ("  total supply          " + (Units (Big $ts.res))) }
if (-not $bal.err) { Out1 ("  held by the contract  " + (Units (Big $bal.res))) }
Out1 ""
Out1 "finished  $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))"
$lines | Out-File $report -Encoding utf8
Start-Sleep -Seconds 3
Write-Host ""
Write-Host "Saved. You can stop the recording now."
