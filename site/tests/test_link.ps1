param([string]$Base = 'http://127.0.0.1:8787')
# Game-to-game link test: two games exchange messages over /v1/link, a phone
# and a wrong token are refused, a kicked game is cut off.
$ErrorActionPreference = 'Stop'
function Get($path) {
  try { return Invoke-RestMethod "$Base$path" }
  catch {
    $r = $_.Exception.Response
    if ($r) { $b = $_.ErrorDetails.Message | ConvertFrom-Json; $b | Add-Member status ([int]$r.StatusCode); return $b }
    throw
  }
}
function Check($cond, $what) { if (-not $cond) { throw "FAIL: $what" }; Write-Output "ok  $what" }
$wsBase = $Base -replace '^http', 'ws'
function Connect($code, $token) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  try {
    $ws.ConnectAsync([Uri]"$wsBase/v1/link?code=$code&token=$token", [Threading.CancellationToken]::None).Wait(5000) | Out-Null
  } catch { return $null }
  if ($ws.State -ne 'Open') { return $null }
  return $ws
}
function Send($ws, $text) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($text)
  $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, [Threading.CancellationToken]::None).Wait(5000) | Out-Null
}
function Receive($ws, $ms = 3000) {
  $buf = New-Object byte[] 8192
  try {
    $task = $ws.ReceiveAsync([ArraySegment[byte]]$buf, [Threading.CancellationToken]::None)
    if (-not $task.Wait($ms)) { return $null }
  } catch { return '<closed>' }
  if ($task.Result.MessageType -eq 'Close') { return '<closed>' }
  return [Text.Encoding]::UTF8.GetString($buf, 0, $task.Result.Count)
}

$h = Get '/v1/create?name=Host&sid=76561198000000001'
$code = $h.code
$g = Get "/v1/join?code=$code&name=Guest"
$p = Get "/v1/join?code=$code&name=Phone&kind=phone"

$wh = Connect $code $h.token
$wg = Connect $code $g.token
Check ($wh -and $wg) 'host and guest games open the link'
Check (-not (Connect $code $p.token)) 'a phone cannot open the link'
Check (-not (Connect $code '0123456789abcdef0123456789abcdef')) 'a wrong token cannot open the link'

Send $wh 'S|1|Fables101|AndersenWoodsmanAptNight|8'
Check ((Receive $wg) -eq "0`tS|1|Fables101|AndersenWoodsmanAptNight|8") 'guest gets the host message with the sender id'
Send $wg 'W'
Check ((Receive $wh) -eq "1`tW") 'host gets the guest message'
Send $wh ('x' * 5000)
Check ($null -eq (Receive $wg 1500)) 'an oversized message is dropped'

$null = Get "/v1/kick?code=$code&token=$($h.token)&id=1"
Send $wg 'after kick'
$r = Receive $wg 3000
Check ($r -eq '<closed>' -or $null -eq (Receive $wh 1500)) 'a kicked game is cut off'
Write-Output 'link tests passed'
