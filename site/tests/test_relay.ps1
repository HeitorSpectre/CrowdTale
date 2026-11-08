param([string]$Base = 'http://127.0.0.1:8787')
# Integration test for the co-op relay: 4 players, votes, tie rule, fallback,
# applied marker, late joiner, full room, bad tokens and bad codes.
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

$hostRoom = Get '/v1/create?rid=7&name=Heitor%20%3Cb%3E&sid=76561198000000001'
Check ($hostRoom.ok -and $hostRoom.code.Length -eq 6 -and $hostRoom.rid -eq 7) "create returns 6-char code and echoes rid ($($hostRoom.code))"
$code = $hostRoom.code; $ht = $hostRoom.token
$pretty = $code.Substring(0,3) + '-' + $code.Substring(3).ToLower()
Check ((Get "/v1/check?code=$pretty&kind=game").ok) 'check finds the room before joining'
$g1 = Get "/v1/join?code=$pretty&name=Jo%C3%A3o&sid=local-48002"
Check ($g1.ok -and $g1.id -eq 1 -and $g1.role -eq 'guest') 'join accepts dashed lowercase code'
$g2 = Get "/v1/join?code=$code"; $g3 = Get "/v1/join?code=$code"
Check ((Get "/v1/state?code=$code&token=$ht").players -eq 4) 'four players in room'
Check ((Get "/v1/check?code=$code&kind=game").error -eq 'session is full') 'check says a full room is full'
Check ((Get "/v1/check?code=$code&kind=phone").ok) 'check still has seats for phones'
$st = Get "/v1/state?code=$code&token=$ht"
Check ($st.names[0].name -eq 'Heitor b' -and $st.names[0].host -and $st.names[1].name -eq ([string][char]0x4A + 'o' + [char]0xE3 + 'o')) "names sanitized and kept ($($st.names.name -join ', '))"
Check ($st.names[2].name -eq 'Player 3') 'missing name gets a default'
Check ($st.names[0].sid -eq '76561198000000001' -and $st.names[1].sid -eq 'local-48002' -and -not $st.names[2].sid) 'games see the peer ids of games'
Check ((Get "/v1/join?code=$code").status -eq 409) 'fifth player refused'
Check ((Get "/v1/poll?code=$code&token=$($g1.token)&count=3").status -eq 403) 'guest cannot open votes'
Check ((Get "/v1/state?code=$code&token=0123456789abcdef0123456789abcdef").status -eq 403) 'wrong token refused'

$p = Get "/v1/poll?code=$code&token=$ht&count=3"
$seq = $p.seq
$null = Get "/v1/vote?code=$code&token=$ht&seq=$seq&index=0"
$null = Get "/v1/vote?code=$code&token=$($g1.token)&seq=$seq&index=1"
$null = Get "/v1/vote?code=$code&token=$($g2.token)&seq=$seq&index=1"
$null = Get "/v1/vote?code=$code&token=$($g3.token)&seq=$seq&index=2"
$view = Get "/v1/state?code=$code&token=$($g2.token)"
Check (($view.poll.votes -join ',') -eq '1,2,1' -and $view.poll.mine -eq 1) 'guest sees tally and own vote'
Check ((Get "/v1/vote?code=$code&token=$ht&seq=$seq&index=7").status -eq 400) 'out-of-range vote refused'
Check ((Get "/v1/resolve?code=$code&token=$($g1.token)&seq=$seq").status -eq 403) 'guest cannot close votes'
$r = Get "/v1/resolve?code=$code&token=$ht&seq=$seq"
Check ($r.result -eq 1) 'majority wins'
Check ((Get "/v1/state?code=$code&token=$($g3.token)").poll.result -eq 1) 'guests receive result'
Check ((Get "/v1/vote?code=$code&token=$($g3.token)&seq=$seq&index=0").status -eq 400) 'vote after close refused'

$phone = Get "/v1/join?code=$code&kind=phone&name=Ana&sid=76561198000000009"
Check (-not ((Get "/v1/state?code=$code&token=$($phone.token)").names | Where-Object { $_.sid })) 'phones never see peer ids'
Check ($phone.ok -and $phone.role -eq 'phone' -and $phone.id -ge 10) 'phone joins beside a full PC room'
$web = Get "/v1/join?code=$code&kind=web&name=Leo"
Check ($web.ok -and $web.role -eq 'web' -and ($web.names | Where-Object { $_.name -eq 'Leo' }).kind -eq 'web') 'computer browser joins as web'
$null = Get "/v1/leave?code=$code&token=$($web.token)"
$pt = Get "/v1/poll?code=$code&token=$ht&count=3&secs=20&t0=%5BHey%20Toad.%5D&t1=&t2=%3Cscript%3EEnough%20excuses"
$ps = Get "/v1/state?code=$code&token=$($phone.token)"
Check ($ps.poll.texts[0] -eq '[Hey Toad.]' -and $ps.poll.texts[1] -eq '' -and $ps.poll.texts[2] -eq 'scriptEnough excuses' -and $ps.poll.remaining -ge 19) 'choice texts sanitized, countdown sent'
Check ((Get "/v1/vote?code=$code&token=$($phone.token)&seq=$($pt.seq)&index=1").status -eq 400) 'hidden choice cannot be voted'
$null = Get "/v1/pause?code=$code&token=$ht&paused=1"
$pv = (Get "/v1/state?code=$code&token=$($phone.token)").poll
Start-Sleep -Seconds 2
$pv2 = (Get "/v1/state?code=$code&token=$($phone.token)").poll
Check ($pv.paused -and $pv2.remaining -eq $pv.remaining) 'pause freezes the countdown'
Check ((Get "/v1/pause?code=$code&token=$($phone.token)&paused=1").status -eq 403) 'only the host pauses'
$null = Get "/v1/pause?code=$code&token=$ht&paused=0"
Check (-not (Get "/v1/state?code=$code&token=$($phone.token)").poll.paused) 'resume clears the pause'
$null = Get "/v1/state?code=$code&token=$ht&where=menu"
Check ((Get "/v1/state?code=$code&token=$($phone.token)").hostWhere -eq 'menu') 'host location reported to phones'
$null = Get "/v1/state?code=$code&token=$($g1.token)&where=paused"
Check ((Get "/v1/state?code=$code&token=$($phone.token)").hostWhere -eq 'menu') 'only the host reports its location'
$before = (Get "/v1/state?code=$code&token=$ht&where=game").poll.remaining
Start-Sleep -Seconds 4
$frozen = Get "/v1/state?code=$code&token=$($phone.token)"
Check ($frozen.poll.paused -and $frozen.hostWhere -eq 'paused' -and $frozen.poll.remaining -ge $before - 1) 'silent host freezes the countdown'
$back = (Get "/v1/state?code=$code&token=$ht").poll
Check (-not $back.paused -and $back.remaining -ge $before - 1) 'frozen time is given back'
$null = Get "/v1/vote?code=$code&token=$($phone.token)&seq=$($pt.seq)&index=2"
$ps = Get "/v1/state?code=$code&token=$ht"
Check ($ps.poll.voters[0].name -eq 'Ana' -and $ps.poll.voters[0].kind -eq 'phone' -and $ps.players -eq 5) 'host sees phone voter by name'
Check ((Get "/v1/kick?code=$code&token=$($g1.token)&id=2").status -eq 403) 'guest cannot kick'
$null = Get "/v1/kick?code=$code&token=$ht&id=$($phone.id)"
$gone = Get "/v1/state?code=$code&token=$($phone.token)"
Check ($gone.status -eq 403 -and $gone.error -eq 'removed by the host') 'kicked player is told why'
$seq2 = (Get "/v1/poll?code=$code&token=$ht&count=2").seq
$null = Get "/v1/vote?code=$code&token=$ht&seq=$seq2&index=1"
$null = Get "/v1/vote?code=$code&token=$($g1.token)&seq=$seq2&index=0"
Check ((Get "/v1/resolve?code=$code&token=$ht&seq=$seq2").result -eq 1) 'tie goes to host vote'

$seq3 = (Get "/v1/poll?code=$code&token=$ht&count=6").seq
Check ((Get "/v1/resolve?code=$code&token=$ht&seq=$seq3").status -eq 400) 'empty vote needs fallback'
Check ((Get "/v1/resolve?code=$code&token=$ht&seq=$seq3&fallback=4").result -eq 4) 'fallback default used'

$null = Get "/v1/applied?code=$code&token=$($g1.token)&seq=$seq3"
Check ((Get "/v1/state?code=$code&token=$($g1.token)").applied -eq $seq3) 'applied marker stored'
$null = Get "/v1/leave?code=$code&token=$($g3.token)"
$late = Get "/v1/join?code=$code"
Check ($late.ok -and $late.applied -eq $seq3) 'late joiner starts after last decided vote'

Check ((Get '/v1/join?code=ABC').status -eq 400) 'malformed code refused'
Check ((Get '/v1/join?code=222222').status -eq 404) 'unknown room refused'
$ck = Get '/v1/check?code=222222'; Check ($ck.ok -eq $false -and $ck.error -eq 'session not found' -and -not $ck.status) 'check answers 200 for an unknown code (game sees it)'
Check ((Get "/v1/nothing?code=$code").status -eq 404) 'unknown endpoint refused'
$null = Get "/v1/leave?code=$code&token=$ht"
Check ((Get "/v1/state?code=$code&token=$($g1.token)").status -eq 404) 'host leaving closes the room'
Write-Output 'PASS: relay'
