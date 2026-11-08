local kLinkUrl = "http://127.0.0.1:" .. tostring(gCoopLinkPort or 47892)
local kTimeout = 1.5
local kRetryAbsent = 30
local mBusy = false
local mBusyAt = 0
local mRid = (os.time() % 100000) * 1000 + 500
local mInbox = {}
local mInfo
local mInfoAt
local mAbsentAt
local mPeers

function CoopLink_OnReply(body)
  if type(body) == "string" and #body < 65536 then
    table.insert(mInbox, body)
    if #mInbox > 8 then
      table.remove(mInbox, 1)
    end
  end
end

local function NextFrame()
  if WaitForNextFrame then
    WaitForNextFrame()
  else
    Yield()
  end
end

local function Call(path, params)
  while mBusy and GetTotalTime() - mBusyAt < kTimeout + 1 do
    NextFrame()
  end
  mBusy = true
  mBusyAt = GetTotalTime()
  mRid = mRid + 1
  local rid = mRid
  mInbox = {}
  local url = kLinkUrl .. path .. "?rid=" .. tostring(rid)
  if params and params ~= "" then
    url = url .. "&" .. params
  end
  local result
  if pcall(HttpGetAsync, url, "CoopLink_OnReply") then
    local waited = 0
    while waited < kTimeout and not result do
      NextFrame()
      waited = waited + GetFrameTime()
      while 0 < #mInbox and not result do
        local body = table.remove(mInbox, 1)
        local ok, reply = pcall(HttpParseJson, body)
        if ok and type(reply) == "table" and tonumber(reply.rid) == rid then
          result = reply
        end
      end
    end
  end
  mBusy = false
  return result
end

function CoopLink_Hello()
  if mInfo and GetTotalTime() - mInfoAt < 60 then
    return mInfo
  end
  if mAbsentAt and GetTotalTime() - mAbsentAt < kRetryAbsent then
    return nil
  end
  local reply = Call("/v1/hello")
  if reply and reply.ok == true then
    mInfo = {
      steam = reply.steam == true,
      name = type(reply.name) == "string" and reply.name or nil,
      id = type(reply.id) == "string" and reply.id or nil,
      mode = tostring(reply.mode or "steam"),
      autoqte = reply.autoqte == true and reply.mode == "local",
      relay = reply.relay == true
    }
    mInfoAt = GetTotalTime()
    mAbsentAt = nil
    return mInfo
  end
  mInfo = nil
  mAbsentAt = GetTotalTime()
  return nil
end

function CoopLink_Info()
  return mInfo
end

function CoopLink_CanInvite()
  return mInfo ~= nil and mInfo.steam and mInfo.mode == "steam"
end

function CoopLink_SteamName()
  local info = CoopLink_Hello()
  if info and info.steam and info.mode == "steam" and info.name and info.name ~= "" then
    return info.name
  end
  return nil
end

function CoopLink_PeerId()
  local info = CoopLink_Hello()
  return info and info.id or nil
end

function CoopLink_Host(code)
  if CoopLink_Hello() then
    Call("/v1/host", "code=" .. tostring(code))
  end
end

function CoopLink_Invite()
  if not CoopLink_Hello() then
    return false
  end
  local reply = Call("/v1/invite")
  return reply ~= nil and reply.ok == true
end

function CoopLink_Leave()
  mPeers = nil
  mRelayKey = nil
  if CoopLink_Hello() then
    Call("/v1/leave")
  end
end

function CoopLink_TakePending()
  if not CoopLink_Hello() then
    return nil
  end
  local reply = Call("/v1/pending")
  if reply and reply.ok == true and type(reply.join) == "string" then
    return reply.join
  end
  return nil
end

local mRelayKey
function CoopLink_Relay(session)
  if not (session and session.code and session.token) or not CoopLink_Hello() then
    return
  end
  local key = session.code .. ":" .. session.token
  if key == mRelayKey and mInfo.relay then
    return
  end
  local reply = Call("/v1/relay", "base=" .. CoopNet_Encode(gCoopRelayUrl or "") ..
    "&code=" .. CoopNet_Encode(session.code) .. "&token=" .. CoopNet_Encode(session.token))
  if reply and reply.ok == true then
    mRelayKey = key
    mInfo.relay = reply.connected == true
  end
end

function CoopLink_SaveSend()
  if not CoopLink_Hello() then
    return false
  end
  local reply = Call("/v1/savesend")
  if reply and reply.ok == true then
    return true
  end
  if reply and reply.error then
    CoopLink_LogNow("sync: co-op save not sent (" .. tostring(reply.error) .. ")")
  end
  return false
end

function CoopLink_SaveState()
  if not CoopLink_Hello() then
    return nil
  end
  local reply = Call("/v1/saveready")
  if reply and reply.ok == true then
    return { ready = tostring(reply.ready or "0"), sending = reply.sending == true }
  end
  return nil
end

function CoopLink_SetPeers(names)
  if not mInfo then
    return
  end
  local ids = {}
  for _, p in ipairs(names or {}) do
    if p.sid and p.sid ~= "" and p.sid ~= mInfo.id and string.match(p.sid, "^%d+$") then
      table.insert(ids, p.sid)
    end
  end
  table.sort(ids)
  local key = table.concat(ids, ",")
  if key == mPeers then
    return
  end
  mPeers = key
  Call("/v1/peers", "ids=" .. key)
end

function CoopLink_Send(text, to)
  if not mInfo then
    return false
  end
  local reply = Call("/v1/send", "to=" .. CoopNet_Encode(to or "all") .. "&data=" .. CoopNet_Encode(text))
  return reply ~= nil and reply.ok == true
end

function CoopLink_LogNow(text)
  mRid = mRid + 1
  local url = kLinkUrl .. "/v1/log?rid=" .. tostring(mRid) .. "&msg=" ..
    CoopNet_Encode(string.sub(tostring(text), 1, 300))
  pcall(HttpGetAsync, url, "CoopLink_OnReply")
end

function CoopLink_SendNow(text, to)
  if not mInfo then
    return
  end
  mRid = mRid + 1
  local url = kLinkUrl .. "/v1/send?rid=" .. tostring(mRid) .. "&to=" .. CoopNet_Encode(to or "all") ..
    "&data=" .. CoopNet_Encode(text)
  pcall(HttpGetAsync, url, "CoopLink_OnReply")
end

function CoopLink_Log(text)
  if mInfo then
    Call("/v1/log", "msg=" .. CoopNet_Encode(string.sub(tostring(text), 1, 300)))
  end
end

function CoopLink_Receive()
  local list = {}
  if not mInfo then
    return list
  end
  local reply = Call("/v1/recv")
  local msgs = reply and reply.msgs
  if type(msgs) ~= "table" then
    return list
  end
  local i = msgs[0] ~= nil and 0 or 1
  while msgs[i] ~= nil do
    local m = msgs[i]
    if type(m) == "table" and type(m.data) == "string" then
      table.insert(list, { from = tostring(m.from or ""), data = m.data })
    end
    i = i + 1
  end
  return list
end
