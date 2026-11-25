-- LibTTS-1.0: interface between addons that speak (consumers) and addons that supply voices (providers).
-- See docs/LibTTS.md. The client has no completion callback and no per-sound stop or volume, so the library plays clips
-- on its own clock from the durations the provider gives. One queue serves all consumers, so voices never overlap.
local MAJOR, MINOR = "LibTTS-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.providers = lib.providers or {}     -- id -> definition given to RegisterProvider
lib.known = lib.known or {}             -- id -> { addon, name, extension, ... } for providers that may not be loaded yet
lib.tried = lib.tried or {}             -- addon name -> true once LoadAddOn was attempted
lib.queue = lib.queue or {}             -- waiting utterances, highest priority first
lib.listeners = lib.listeners or {}     -- functions told about provider changes
lib.Consumer = lib.Consumer or {}       -- consumer methods; kept in one table so old consumers upgrade with the library
lib.now = lib.now or 0                  -- seconds counted while the queue is busy (for ttl)
lib.timer = lib.timer or 0              -- seconds until the next clip is due

lib.MAX_CLIPS = 600        -- most clips waiting at once, so a chat flood cannot build up minutes of speech
lib.CHUNK_SIZE = 300       -- text longer than this is synthesized one piece at a time, to avoid a long frame
lib.CHUNK_PAUSE = 0.38     -- pause between pieces of long text (scaled by the pause and speed options)
lib.REFILL_CLIPS = 8       -- synthesize the next piece when this few clips are left

local PRIORITY = { low = 1, normal = 2, alert = 3 }
local LIBRARY_OPTIONS = { provider = true, require = true, priority = true, interrupt = true, channel = true, ttl = true,
    key = true, onEvent = true, maxLength = true }

local Consumer = lib.Consumer
local consumerMeta = { __index = Consumer }

local function safeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
end

local function fire(u, event, info)
    if u.onEvent then safeCall(u.onEvent, event, u, info) end
    if u.consumer.callback then safeCall(u.consumer.callback, event, u, info) end
end

local function notify(event, id)
    for _, fn in ipairs(lib.listeners) do safeCall(fn, event, id) end
end

---------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------

local function trim(s) return s and (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function scan()
    if lib.scanned or not GetNumAddOns then return end
    lib.scanned = true
    for i = 1, GetNumAddOns() do
        local id = trim(GetAddOnMetadata(i, "X-LibTTS-Provider"))
        if id and id ~= "" then
            local k = { addon = (GetAddOnInfo(i)), name = trim(GetAddOnMetadata(i, "X-LibTTS-Name")) or id,
                extension = trim(GetAddOnMetadata(i, "X-LibTTS-Extension")),
                language = trim(GetAddOnMetadata(i, "X-LibTTS-Language")),
                gender = trim(GetAddOnMetadata(i, "X-LibTTS-Gender")) }
            local list = GetAddOnMetadata(i, "X-LibTTS-Features")
            if list then
                k.features = {}
                for name in list:gmatch("[^%s,]+") do k.features[name] = true end
            end
            lib.known[id] = k
        end
    end
end

-- "ok", "missing" or "disabled"
local function addonState(name)
    if not name then return "missing" end
    local found, _, _, enabled, _, reason = GetAddOnInfo(name)
    if not found or reason == "MISSING" then return "missing" end
    if not enabled then return "disabled" end
    return "ok"
end

local function loadOnce(name)
    if not name or IsAddOnLoaded(name) or lib.tried[name] then return end
    lib.tried[name] = true
    LoadAddOn(name)
end

-- Registers a loaded provider. def = { name, Synthesize(self, text, options) -> items[, info] or nil, reason, optional:
-- language, gender, quality, features = { name = true or { min, max, default } }, voices, OnStop(self, utterance) }.
function lib:RegisterProvider(id, def)
    if type(id) ~= "string" or id == "" then error("Usage: RegisterProvider(id, def)", 2) end
    if type(def) ~= "table" or type(def.name) ~= "string" or type(def.Synthesize) ~= "function" then
        error("LibTTS provider '" .. id .. "' needs a name and a Synthesize function", 2)
    end
    def.id = id
    def.features = def.features or {}
    local existed = self.providers[id] ~= nil
    self.providers[id] = def
    notify(existed and "provider_updated" or "provider_registered", id)
    return def
end

-- Changes fields of a registered provider; features are merged by name. Extensions use this.
function lib:UpdateProvider(id, patch)
    local def = self.providers[id]
    if not def then error("LibTTS provider '" .. tostring(id) .. "' is not registered", 2) end
    for key, value in pairs(patch) do
        if key == "features" then
            for name, feature in pairs(value) do def.features[name] = feature end
        else
            def[key] = value
        end
    end
    notify("provider_updated", id)
end

-- Tells the library about a provider addon without loading it. TOC fields (X-LibTTS-*) take precedence, so this is for
-- a consumer that wants to name a voice it recommends even when that voice is not installed.
function lib:DeclareProvider(id, info)
    scan()
    if not self.known[id] then self.known[id] = info end
end

-- Calls fn(event, id) on "provider_registered" and "provider_updated".
function lib:RegisterCallback(fn) self.listeners[#self.listeners + 1] = fn end

function lib:IsAvailable(id)
    scan()
    if self.providers[id] then return true end
    local k = self.known[id]
    if not k then return false, "unknown" end
    local state = addonState(k.addon)
    if state == "ok" then return true end
    return false, state
end

-- Loads a provider and its extension. Safe to repeat. Do this at a quiet moment: large voices stall a frame.
function lib:Preload(id)
    scan()
    local k = self.known[id]
    if k then loadOnce(k.addon) end
    if not self.providers[id] then
        local _, reason = self:IsAvailable(id)
        return false, reason or "load_failed"
    end
    if k then loadOnce(k.extension) end
    return true
end

function lib:GetProviderInfo(id)
    scan()
    local k, def = self.known[id], self.providers[id]
    if not k and not def then return nil end
    k, def = k or {}, def or {}
    local available, reason = self:IsAvailable(id)
    return { id = id, name = def.name or k.name or id, addon = k.addon, extension = k.extension,
        language = def.language or k.language, gender = def.gender or k.gender, quality = def.quality,
        voices = def.voices, features = def.features or k.features, loaded = self.providers[id] ~= nil,
        available = available, reason = reason,
        extensionLoaded = k.extension and IsAddOnLoaded(k.extension) and true or false }
end

-- All known providers, loaded or not, sorted by id. filter = { language, gender, require = { feature, ... } }. A provider
-- that has not said what it supports passes the require test; Speak checks again after loading it.
function lib:ListProviders(filter)
    scan()
    local ids, seen, out = {}, {}, {}
    for id in pairs(self.providers) do seen[id] = true; ids[#ids + 1] = id end
    for id in pairs(self.known) do if not seen[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local info = self:GetProviderInfo(id)
        local keep = not (filter and filter.language and info.language and filter.language ~= info.language)
            and not (filter and filter.gender and info.gender and filter.gender ~= info.gender)
        if keep and filter and filter.require and info.features then
            for _, name in ipairs(filter.require) do
                if not info.features[name] then keep = false end
            end
        end
        if keep then out[#out + 1] = info end
    end
    return out
end

function lib:GetFeatures(id)
    local info = self:GetProviderInfo(id)
    return info and info.features or nil
end

---------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------

-- Splits long text at sentence ends, else at spaces.
local function splitText(text, size)
    local chunks, pos = {}, 1
    while #text - pos + 1 > size do
        local window = text:sub(pos, pos + size - 1)
        local piece = window:match("^.*[%.!%?\n]%s") or window:match("^.*%s") or window
        chunks[#chunks + 1] = piece
        pos = pos + #piece
    end
    if pos <= #text then chunks[#chunks + 1] = text:sub(pos) end
    return chunks
end

-- Splits options into what the provider receives and what it does not support.
local function negotiate(def, options)
    local features = def.features
    for _, name in ipairs(options.require or {}) do
        if not features[name] then return nil, "unsupported:" .. name end
    end
    local out, info = {}, { provider = def.id, ignored = {}, clamped = {} }
    for name, value in pairs(options) do
        if not LIBRARY_OPTIONS[name] then
            local feature = features[name]
            if not feature then
                info.ignored[#info.ignored + 1] = name
            else
                if type(value) == "number" and type(feature) == "table" then
                    local limited = math.max(feature.min or value, math.min(feature.max or value, value))
                    if limited ~= value then info.clamped[#info.clamped + 1] = name end
                    value = limited
                end
                out[name] = value
            end
        end
    end
    table.sort(info.ignored)
    table.sort(info.clamped)
    return out, info
end

-- Appends the next piece of text to an utterance. Returns false and a reason on failure.
local function synthesizeNext(u)
    local def = lib.providers[u.provider]
    local chunk = u.chunks[u.nextChunk]
    u.nextChunk = u.nextChunk + 1
    local ok, items, extra = pcall(def.Synthesize, def, chunk, u.options)
    if not ok then
        geterrorhandler()(items)
        return false, "provider_error"
    end
    if type(items) ~= "table" then return false, extra or "synthesis_failed" end
    if type(extra) == "table" then
        for k, v in pairs(extra) do u.info[k] = v end
    end
    local last = u.items[#u.items]
    if last and #items > 0 then
        last.wait = last.wait + lib.CHUNK_PAUSE * (u.options.pause or 1) / (u.options.speed or 1)
    end
    for _, item in ipairs(items) do u.items[#u.items + 1] = item end
    return true
end

local function clipsWaiting()
    local n = 0
    if lib.active then n = #lib.active.items - lib.active.head + 1 end
    for _, u in ipairs(lib.queue) do n = n + #u.items - u.head + 1 end
    return n
end

local function enqueue(u)
    local at = #lib.queue + 1
    for i, other in ipairs(lib.queue) do
        if other.priority < u.priority then at = i; break end
    end
    table.insert(lib.queue, at, u)
end

local function stopActive(reason)
    local u = lib.active
    lib.active = nil
    lib.timer = 0
    local def = lib.providers[u.provider]
    if def and def.OnStop then safeCall(def.OnStop, def, u) end
    fire(u, "interrupted", { reason = reason })
end

-- Removes every utterance that match(u) accepts.
local function remove(match, reason)
    for i = #lib.queue, 1, -1 do
        local u = lib.queue[i]
        if match(u) then
            table.remove(lib.queue, i)
            fire(u, "dropped", { reason = reason })
        end
    end
    if lib.active and match(lib.active) then stopActive(reason) end
end

---------------------------------------------------------------------------
-- Consumers
---------------------------------------------------------------------------

-- name identifies the consumer. Each call returns a separate handle with its own defaults and provider choice.
function lib:NewConsumer(name)
    if type(name) ~= "string" or name == "" then error("Usage: NewConsumer(name)", 2) end
    return setmetatable({ name = name, defaults = {} }, consumerMeta)
end

-- The voice the player prefers, used by every consumer that did not choose one itself. Only for an addon that lets the
-- player pick a voice; the last call wins, nil clears it.
function lib:SetDefaultProvider(id) self.defaultProvider = id end
function lib:GetDefaultProvider() return self.defaultProvider end

-- All providers that pass the require test, the default one first, then by id.
local function candidates(require)
    local list = lib:ListProviders({ require = require })
    for i, info in ipairs(list) do
        if info.id == lib.defaultProvider then
            table.insert(list, 1, table.remove(list, i))
            break
        end
    end
    return list
end

function Consumer:SetProvider(id) self.provider = id end
function Consumer:SetDefaults(options) self.defaults = options or {} end
function Consumer:SetCallback(fn) self.callback = fn end   -- fn(event, utterance, info) for every request of this consumer

-- The provider Speak would use right now without loading anything: the chosen one if loaded, else the default one if
-- loaded, else the first loaded one.
function Consumer:GetActiveProvider()
    if self.provider and lib.providers[self.provider] then return self.provider end
    for _, info in ipairs(candidates()) do
        if info.loaded then return info.id end
    end
end

local function resolve(consumer, options)
    if options.provider then
        if lib:Preload(options.provider) then return options.provider end
        return nil, "unavailable:" .. options.provider
    end
    if consumer.provider and lib:Preload(consumer.provider) then return consumer.provider end
    for _, info in ipairs(candidates(options.require)) do
        if lib:Preload(info.id) then return info.id end
    end
    return nil, "no_provider"
end

-- Loads the provider Speak would use, so its first use does not stall a frame. Returns its id, or nil and a reason.
function Consumer:Preload() return resolve(self, {}) end

-- Queues text. Returns a handle for Stop, or nil and a reason ("no_provider", "unavailable:<id>", "unsupported:<feature>",
-- "provider_error", "queue_full", or "empty" when the text has nothing to say). See docs/LibTTS.md for the options.
function Consumer:Speak(text, options)
    local merged = {}
    for k, v in pairs(self.defaults) do merged[k] = v end
    for k, v in pairs(options or {}) do merged[k] = v end

    local function fail(reason)
        if merged.onEvent then safeCall(merged.onEvent, "failed", nil, { reason = reason }) end
        if self.callback then safeCall(self.callback, "failed", nil, { reason = reason }) end
        return nil, reason
    end

    local id, reason = resolve(self, merged)
    if not id then return fail(reason) end
    local forProvider, info = negotiate(lib.providers[id], merged)
    if not forProvider then return fail(info) end

    text = tostring(text or "")
    if merged.maxLength then text = text:sub(1, merged.maxLength) end
    local u = { consumer = self, provider = id, options = forProvider, info = info, items = {}, head = 1,
        chunks = splitText(text, lib.CHUNK_SIZE), nextChunk = 1, priority = PRIORITY[merged.priority] or PRIORITY.normal,
        channel = merged.channel, key = merged.key, onEvent = merged.onEvent,
        expires = merged.ttl and (lib.now + merged.ttl) or nil }
    if #u.chunks > 0 then
        local ok, why = synthesizeNext(u)
        if not ok then return fail(why) end
    end
    if #u.items == 0 then return nil, "empty" end

    if merged.key then
        remove(function(other) return other.consumer == self and other.key == merged.key end, "replaced")
    end
    if merged.interrupt and lib.active then stopActive("interrupted") end

    local room = lib.MAX_CLIPS - clipsWaiting()
    if room <= 0 then
        fire(u, "dropped", { reason = "queue_full" })
        return nil, "queue_full"
    end
    for i = #u.items, room + 1, -1 do u.items[i] = nil end

    enqueue(u)
    lib.frame:Show()
    return u
end

-- Stop() ends everything from this consumer, Stop(handle) one request. Only speech not yet played can be stopped: the
-- client cannot cut off a clip that already started.
function Consumer:Stop(handle)
    remove(function(u) return u.consumer == self and (not handle or u == handle) end, "stopped")
end

function Consumer:StopChannel(channel)
    remove(function(u) return u.consumer == self and u.channel == channel end, "stopped")
end

-- Holds this consumer's speech at the next clip; other consumers keep playing.
function Consumer:Pause() self.paused = true end
function Consumer:Resume()
    self.paused = nil
    if lib:IsBusy() then lib.frame:Show() end
end

function Consumer:IsBusy()
    if lib.active and lib.active.consumer == self then return true end
    for _, u in ipairs(lib.queue) do
        if u.consumer == self then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Playback
---------------------------------------------------------------------------

function lib:IsBusy() return self.active ~= nil or #self.queue > 0 end

local function takeNext()
    for i, u in ipairs(lib.queue) do
        if not u.consumer.paused then return table.remove(lib.queue, i) end
    end
end

local function expire()
    for i = #lib.queue, 1, -1 do
        local u = lib.queue[i]
        if u.expires and not u.started and lib.now >= u.expires then
            table.remove(lib.queue, i)
            fire(u, "dropped", { reason = "expired" })
        end
    end
end

-- Does one thing that is due. Returns false when nothing more can happen now. Callbacks may call Speak or Stop, so
-- state is read again on every step.
local function step()
    local u = lib.active
    if not u then
        u = takeNext()
        if not u then return false end
        lib.active = u
        if not u.started then
            u.started = true
            fire(u, "started", u.info)
        end
        return true
    end
    if u.consumer.paused then
        lib.active = nil
        table.insert(lib.queue, 1, u)
        return true
    end
    if u.head > #u.items then
        if u.nextChunk <= #u.chunks then
            local ok, why = synthesizeNext(u)
            if not ok then u.chunks, u.failure = {}, why end
            return true
        end
        lib.active = nil
        if u.failure then fire(u, "failed", { reason = u.failure }) else fire(u, "finished", u.info) end
        return true
    end
    local item = u.items[u.head]
    u.head = u.head + 1
    PlaySoundFile(item.path)
    lib.timer = lib.timer + item.wait
    if item.mark then fire(u, "mark", { mark = item.mark }) end
    return true
end

function lib:Tick(elapsed)
    self.now = self.now + elapsed
    self.timer = self.timer - elapsed
    expire()
    while self.timer <= 0 and step() do end
    local u = self.active
    if u and u.nextChunk <= #u.chunks and #u.items - u.head < self.REFILL_CLIPS then
        local ok, why = synthesizeNext(u)
        if not ok then u.chunks, u.failure = {}, why end   -- clips already made still play, then "failed" ends the request
    end
    if self.active then return end
    if self.timer < 0 then self.timer = 0 end
    for _, waiting in ipairs(self.queue) do
        if not waiting.consumer.paused then return end
    end
    self.frame:Hide()
end

lib.frame = lib.frame or CreateFrame("Frame")
lib.frame:SetScript("OnUpdate", function(_, elapsed) lib:Tick(elapsed) end)
if not lib:IsBusy() then lib.frame:Hide() end
