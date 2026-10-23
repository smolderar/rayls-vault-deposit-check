$Host.UI.RawUI.WindowTitle = "Code dump"
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$RPC = "https://mainnet-rpc.rayls.com"
$log = Join-Path $PSScriptRoot "code-dump-log.txt"
"started $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) UTC" | Out-File $log -Encoding utf8
function Log($m) { Write-Host $m; $m | Out-File $log -Append -Encoding utf8 }
function Rpc($method, $params) {
  $body = '{"jsonrpc":"2.0","id":1,"method":"' + $method + '","params":' + $params + '}'
  try { $r = Invoke-RestMethod -Uri $RPC -Method Post -ContentType "application/json" -Body $body -TimeoutSec 60 } catch { return $null }
  return $r.result
}
$targets = @(@("old","0x39ffae6736a9477797548a17019d544c3dbe9f67"), @("new","0x39bf309dba73c90f93f9af74eedb673f53447acb"))
foreach ($t in $targets) {
  $code = Rpc "eth_getCode" ('["' + $t[1] + '","latest"]')
  if ($code) { $code | Out-File (Join-Path $PSScriptRoot ("code-" + $t[0] + ".hex")) -Encoding ascii; Log ("code-" + $t[0] + ".hex saved, " + (($code.Length - 2) / 2) + " bytes") } else { Log "could not read code for $($t[0])" }
  $v = Rpc "eth_call" ('[{"to":"' + $t[1] + '","data":"0xffa1ad74"},"latest"]')
  Log ("VERSION() called directly on " + $t[0] + " implementation: " + $v)
}
Log "Finished. You can close this window."
