-- Bags: the record of each character's bags, bank and money, for the stored views
-- and the tooltip counts. Doc headings are ClassicAPI's docs/API.md.
-- GAP: no DLL keeps the last-seen bags and bank of the account's characters ("The
-- main bank and the bank bags are available only while the bank window is open",
-- ### C_Container.GetContainerNumFreeSlots). A DLL should keep them per character,
-- readable by name, with item counts. The windows read them only through Store.
if not CLASSIC_API_VERSION then error("Bags needs ClassicAPI.", 0) end

local _, B = ...
BagsStore = BagsStore or {} -- restored first: LoadSavedVariablesFirst
local Store = {}
B.Store = Store

local realm, me, owners
local index, dirty, buf = {}, {}, {} -- index[name][itemID] = { bags, bank }
local function Realm()
    if not realm then
        realm, me = GetRealmName(), UnitName("player")
        BagsStore[realm] = BagsStore[realm] or {}
    end
    return BagsStore[realm]
end
function Store.Me() Realm(); return me end

local function Char(name, create)
    local c = Realm()[name]
    if not c and create then c = { bags = {} }; Realm()[name] = c end
    if c and not c.bags then c.bags = {} end
    return c
end
function Store.Bag(owner, bag) local c = Char(owner); return c and c.bags[bag] end
function Store.Money(owner) local c = Char(owner); return c and c.money or 0 end
function Store.Total()
    local sum = 0
    for _, c in pairs(Realm()) do sum = sum + (c.money or 0) end
    return sum
end

-- The characters of this realm, you first.
function Store.Owners()
    if not owners then
        Store.Me()
        owners = { me }
        for name in pairs(Realm()) do if name ~= me then owners[#owners + 1] = name end end
        table.sort(owners, function(a, b) if a == me or b == me then return a == me and b ~= me end return a < b end)
    end
    return owners
end

function Store.Forget(name)
    if name == Store.Me() then return end
    Realm()[name], index[name], owners = nil, nil, nil
end

-- A slot as stored: the item ID, or id:enchant:suffix:unique when
-- one of those is set, then ",count" above 1.
local function Short(link)
    local id, e, s, u = string.match(link or "", "item:(%-?%d+):(%-?%d*):(%-?%d*):(%-?%d*)")
    if not id then return nil end
    if (e == "0" or e == "") and (s == "0" or s == "") and (u == "0" or u == "") then return id end
    return id .. ":" .. e .. ":" .. s .. ":" .. u
end

local function Full(short) return "item:" .. short .. (string.find(short, ":", 1, true) and "" or ":0:0:0") end

-- The link ("item:...") and count of a stored slot, and the link of a stored bag.
function Store.Slot(owner, bag, slot)
    local rec = Store.Bag(owner, bag)
    local s = rec and rec[slot]
    if type(s) ~= "string" then return nil end
    local short, count = string.match(s, "^([^,]+),?(%d*)$")
    if short then return Full(short), tonumber(count) or 1 end
end
function Store.Link(owner, bag)
    local rec = Store.Bag(owner, bag)
    return rec and type(rec.link) == "string" and Full(rec.link) or nil
end

function Store.SaveBag(bag)
    local c = Char(Store.Me(), true)
    dirty[me] = true
    local size = C_Container.GetContainerNumSlots(bag)
    if size == 0 then c.bags[bag] = nil; return end
    local rec = c.bags[bag] or {}
    table.wipe(rec)
    rec.size = size
    if bag > 0 then rec.link = Short(GetInventoryItemLink("player", ContainerIDToInventoryID(bag))) end
    for slot = 1, size do
        local item = C_Container.GetContainerItemInfo(bag, slot, buf)
        local s = item and Short(item.hyperlink)
        if s then rec[slot] = item.stackCount > 1 and s .. "," .. item.stackCount or s end
    end
    c.bags[bag] = rec
end
function Store.SaveBags()
    for bag = 0, 4 do Store.SaveBag(bag) end
    Char(me, true).money = GetMoney()
end
function Store.SaveBank()
    Store.SaveBag(-1)
    for bag = 5, 10 do Store.SaveBag(bag) end
end

-- What a character carries of each item, built at the first tooltip that needs it.
local function Counts(name)
    if index[name] and not dirty[name] then return index[name] end
    local own, c = {}, Char(name)
    for bag, rec in pairs(c and c.bags or own) do
        local bank = bag == -1 or bag >= 5
        for slot, s in pairs(rec) do
            local id = type(slot) == "number" and type(s) == "string" and tonumber(string.match(s, "^(%d+)"))
            if id then
                local t = own[id] or { 0, 0 }
                own[id] = t
                local n = tonumber(string.match(s, ",(%d+)$")) or 1
                if bank then t[2] = t[2] + n else t[1] = t[1] + n end
            end
        end
    end
    index[name], dirty[name] = own, nil
    return own
end

-- Other characters' bags and banks, and your own bank, in item tooltips.
local function OnItem()
    local _, link, id = this:GetItem()
    if not id or this.bagsItem == link then return end
    this.bagsItem = link
    local added
    for _, name in ipairs(Store.Owners()) do
        local t = Counts(name)[id]
        if t and name == me and t[2] > 0 then
            this:AddLine("Bank: " .. t[2], 1, 1, 0)
            added = true
        elseif t and name ~= me then
            this:AddLine(name .. " has" .. (t[1] > 0 and " " .. t[1] .. " (Bags)" or "")
                .. (t[2] > 0 and " " .. t[2] .. " (Bank)" or ""), 1, 1, 0)
            added = true
        end
    end
    if added then this:Show() end
end
local function OnCleared() this.bagsItem = nil end
for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    tip:HookScript("OnTooltipSetItem", OnItem)
    tip:HookScript("OnTooltipCleared", OnCleared)
end
