-- Bags: the inventory and bank windows, from one builder. A window listens only
-- while it shows, redraws only the bags that changed, once per frame, and lays
-- itself out again only when a bag's size changes. Doc headings: ClassicAPI's docs/API.md.
local _, B = ...
local Store = B.Store
local COLS, STEP = 12, 40 -- a 37-pixel slot and 3 of space
local BACKDROP = { bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }
local Window = {}

function Window:Owner() return self.owner or Store.Me() end
function Window:Live() return not self.owner and (self.kind == "inventory" or B.atBank) end

-- Opened by hand, or by itself (a merchant, the mailbox): only the second closes by itself.
function Window:Open(auto, owner)
    if owner ~= nil then self.owner = owner ~= Store.Me() and owner or nil end
    if self:IsShown() then
        if not auto then self.auto = nil end
        return self:Refresh()
    end
    self.auto = auto
    self:Show()
end
function Window:Close(auto) if not auto or self.auto then self:Hide() end end
function Window:Toggle() if self:IsShown() then self:Hide() else self:Open() end end

local function Size(w, bag)
    if bag == -2 then return BagsDB.keys and w:Live() and GetKeyRingSize() or 0 end -- the keys, when shown
    if w:Live() then return C_Container.GetContainerNumSlots(bag) end
    local rec = Store.Bag(w:Owner(), bag)
    return rec and tonumber(rec.size) or 0
end

local function Resized(w)
    if w.drawnOwner ~= w.owner or w.wasLive ~= w:Live() or w.hadBar ~= BagsDB.bagBar[w.kind] then return true end
    for _, bag in ipairs(w.bags) do if Size(w, bag) ~= w.holders[bag].size then return true end end
end

local function Free(w)
    local free, total = 0, 0
    for _, bag in ipairs(w.bags) do
        local h = w.holders[bag]
        h.free = 0
        for slot = 1, h.size do if not h.buttons[slot].hasItem then h.free = h.free + 1 end end
        if bag ~= -2 then free, total = free + h.free, total + h.size end -- keys do not count as space
    end
    if w.freeSlots ~= free or w.totalSlots ~= total then -- no new text while nothing changes
        w.freeSlots, w.totalSlots = free, total
        w.free:SetText(total - free .. " / " .. total .. " Used")
    end
end

-- Every slot in a grid of 12, the bag bar above it when shown.
local function Layout(w)
    local top, n = BagsDB.bagBar[w.kind] and 64 or 30, 0
    B.BagBar(w)
    for _, bag in ipairs(w.bags) do
        local h = w.holders[bag]
        h.size = Size(w, bag)
        for slot = 1, h.size do
            local b = B.Button(h, slot)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", w, "TOPLEFT", 8 + n % COLS * STEP, -top - math.floor(n / COLS) * STEP)
            b:Show()
            n = n + 1
        end
        for slot = h.size + 1, #h.buttons do h.buttons[slot]:Hide() end
    end
    w:SetWidth(COLS * STEP + 13)
    w:SetHeight(top + math.max(1, math.ceil(n / COLS)) * STEP + 33)
    w.drawnOwner, w.wasLive, w.hadBar = w.owner, w:Live(), BagsDB.bagBar[w.kind]
end

local function DrawBag(w, bag, what)
    local h, owner = w.holders[bag], not w:Live() and w:Owner() or nil
    for slot = 1, h.size do B.Draw(h.buttons[slot], owner, what) end
end

-- What changed since the last frame: bags (w.dirty), locks, search and new items
-- (w.light), cooldowns (w.cool), or the shape (w.relayout).
local function Flush(w)
    w.armed = nil
    if w:IsShown() then
        local live = w:Live()
        if w.relayout or Resized(w) then
            Layout(w)
            for _, bag in ipairs(w.bags) do DrawBag(w, bag) end
            if live and w.kind == "bank" then Store.SaveBank() end
        else
            for bag in pairs(w.dirty) do
                DrawBag(w, bag)
                if live and w.kind == "bank" then Store.SaveBag(bag) end
            end
            if w.light or w.cool then
                for _, bag in ipairs(w.bags) do DrawBag(w, bag, (w.light and w.cool) and "all" or w.light and "light" or "cool") end
            end
            if w.light then B.BagBar(w) end -- a bag picked up is locked
        end
        Free(w)
    end
    table.wipe(w.dirty)
    w.relayout, w.light, w.cool = nil, nil, nil
end
local function Arm(w) if not w.armed then w.armed = true; C_Timer.After(0, w.flush) end end

local LIVE = { "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CLOSED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
    "INVENTORY_SEARCH_UPDATE", "GET_ITEM_INFO_RECEIVED" }
local function Listen(w, on)
    local live = on and w:Live()
    for _, e in ipairs(LIVE) do if live then w:RegisterEvent(e) else w:UnregisterEvent(e) end end
    if on and not live then w:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    local new, bank = live and w.kind == "inventory", live and w.kind == "bank"
    if new then w:RegisterEvent("BAG_NEW_ITEMS_UPDATED") else w:UnregisterEvent("BAG_NEW_ITEMS_UPDATED") end
    for _, e in ipairs({ "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED" }) do
        if bank then w:RegisterEvent(e) else w:UnregisterEvent(e) end
    end
end

local function OnEvent(w, event, bag)
    if event == "BAG_UPDATE" then
        if w.holders[bag] then w.dirty[bag] = true end
    elseif event == "BAG_UPDATE_DELAYED" then
        Flush(w)
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        w.dirty[-1] = true; Arm(w)
    elseif event == "BAG_CLOSED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        w.relayout = true; Arm(w) -- a bag taken out fires no BAG_UPDATE_DELAYED
    elseif event == "BAG_UPDATE_COOLDOWN" then
        w.cool = true; Arm(w)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if w.missing then w.missing = nil; for _, b in ipairs(w.bags) do w.dirty[b] = true end; Arm(w) end
    else
        w.light = true; Arm(w) -- ITEM_LOCK_CHANGED, INVENTORY_SEARCH_UPDATE, BAG_NEW_ITEMS_UPDATED
    end
end

-- The live money, which you can pick up; a stored character's, which you cannot.
local function MoneyType(money, kind) local old = this; this = money; MoneyFrame_SetType(kind); this = old end
local function Money(w)
    local live = not w.owner
    MoneyType(w.money, live and "PLAYER" or "STATIC")
    w.money.staticMoney = Store.Money(w:Owner())
    MoneyFrame_Update(w.money:GetName(), live and GetMoney() or w.money.staticMoney)
end
local function MoneyTip()
    if #Store.Owners() < 2 then return end
    GameTooltip:SetOwner(this, B.Side(this))
    GameTooltip:SetText("Total on " .. GetRealmName())
    SetTooltipMoney(GameTooltip, Store.Total() - Store.Money(Store.Me()) + GetMoney())
    GameTooltip:Show()
end

function Window:Refresh()
    if not self:IsShown() then return end
    Listen(self, true)
    self.relayout = true
    Flush(self)
    Money(self)
    local name = self:Owner()
    self.title:SetText(name .. (self.kind == "bank" and "'s Bank" or "'s Inventory"))
    self.menu:SetShown(#Store.Owners() > 1)
    local live = self:Live()
    self.sort:SetEnabled(live)
    self.search:EnableMouse(live)
    self.search:SetAlpha(live and 1 or 0.4)
    if not live then self.search:ClearFocus() end
    if self.bankButton then self.bankButton:SetEnabled(B.atBank or Store.Bag(name, -1) ~= nil) end
end

local function Button(w, text, width, onClick, tip)
    local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    b:SetSize(width, 18)
    b:SetText(text)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function() onClick(w, arg1) end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(tip[1], 1, 1, 1)
        if tip[2] then GameTooltip:AddLine(tip[2]) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Sort(w, button)
    if button == "RightButton" then
        C_Container.SetSortBagsRightToLeft(not C_Container.GetSortBagsRightToLeft())
    elseif w.kind == "bank" then
        if B.atBank then C_Container.SortBankBags() end
    else
        C_Container.SortBags()
    end
end
local function ToggleKeys(w) BagsDB.keys = not BagsDB.keys; w:Refresh() end
local function ToggleBar(w)
    if IsShiftKeyDown() and w.kind == "inventory" then return ToggleKeys(w) end
    BagsDB.bagBar[w.kind] = not BagsDB.bagBar[w.kind]; w:Refresh()
end
local function ToggleBank(w) if B.bank:IsShown() then B.bank:Hide() else B.bank:Open(nil, w:Owner()) end end

local function FreeTip()
    local w = this:GetParent()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Slots used", 1, 1, 1)
    for _, bag in ipairs(w.bags) do
        local h = w.holders[bag]
        if h.size > 0 then
            local r, g = 1, 1
            if h.free == 0 then g = 0.1 elseif h.free <= 2 then g = 0.82 end
            GameTooltip:AddDoubleLine(bag == 0 and "Backpack" or bag == -1 and "Bank" or bag == -2 and "Keys" or "Bag " .. (bag > 4 and bag - 4 or bag),
                h.size - h.free .. " / " .. h.size, 1, 1, 1, r, g, g == 1 and 1 or 0.1)
        end
    end
    GameTooltip:Show()
end

local function Menu(w)
    local function Shown(name) return name == w:Owner() end
    local function Pick(name) w:Open(nil, name) end
    local function Forget()
        local name = w:Owner()
        Store.Forget(name)
        for _, other in ipairs({ B.inventory, B.bank }) do if other.owner == name then other.owner = nil; other:Refresh() end end
    end
    w.menu = CreateFrame("DropdownButton", nil, w, "WowStyle1ArrowDropdownTemplate")
    w.menu:SetupMenu(function(_, root)
        for _, name in ipairs(Store.Owners()) do root:CreateRadio(name, Shown, Pick, name) end
        if w.owner then root:CreateButton("Forget " .. w.owner, Forget) end
    end)
end

function B.NewWindow(kind, name, bags, x, y)
    local w = CreateFrame("Frame", name, UIParent)
    for k, f in pairs(Window) do w[k] = f end
    w.kind, w.bags, w.holders, w.dirty = kind, bags, {}, {}
    for _, bag in ipairs(bags) do
        local h = CreateFrame("Frame", nil, w) -- the stock slot handlers read the bag from the parent's ID
        h:SetAllPoints(w)
        h:SetID(bag)
        h.buttons, h.size = {}, 0
        w.holders[bag] = h
    end
    w:Hide()
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:SetClampedToScreen(true)
    w:SetBackdrop(BACKDROP)
    local alpha = kind == "bank" and 1 or 0.81
    w:SetBackdropColor(0, 0, 0, alpha)
    w:SetBackdropBorderColor(1, 1, 1, alpha)
    -- The first place; a place the player dragged is the client's (layout-cache.txt).
    if not w:IsUserPlaced() then w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y) end
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function() this:StartMoving() end)
    w:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    local function Run() Flush(w) end -- made once: errors reach the error handler
    w.flush = function() xpcall(Run, geterrorhandler()) end
    w:SetScript("OnEvent", OnEvent)
    w:SetScript("OnShow", function() PlaySound("igBackPackOpen"); this:Refresh() end)
    w:SetScript("OnHide", function()
        PlaySound("igBackPackClose")
        Listen(this, false)
        this.owner, this.auto = nil, nil
        this.search:SetText("")
        this.search:ClearFocus()
        if this.kind == "inventory" then C_NewItems.ClearAll() end
        if this.kind == "bank" and B.atBank then CloseBankFrame() end
    end)
    tinsert(UISpecialFrames, name)

    Menu(w)
    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.title:SetPoint("LEFT", w, "TOPLEFT", 14, -18) -- level with the buttons, over the first slot
    w.menu:SetPoint("LEFT", w.title, "RIGHT", 2, 0) -- the character menu follows the name
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() w:Hide() end)
    w.sort = Button(w, "Sort", 40, Sort, { "Sort", "Right-click: fill from the other end" })
    w.sort:SetPoint("RIGHT", close, "LEFT", 0, 0)
    local bar = Button(w, "Bags", 40, ToggleBar, { "Show or hide the bags", "Shift-click: show or hide your keys" })
    w.barButton = bar
    -- Left to right: Bags, Bank, Keys, a gap, Sort.
    if kind == "inventory" then
        w.keysButton = Button(w, "Keys", 40, ToggleKeys, { "Keys", "Show or hide your key ring" })
        w.keysButton:SetPoint("RIGHT", w.sort, "LEFT", -14, 0)
        w.bankButton = Button(w, "Bank", 40, ToggleBank, { "Bank", "Your bank as you last saw it" })
        w.bankButton:SetPoint("RIGHT", w.keysButton, "LEFT", -2, 0)
        bar:SetPoint("RIGHT", w.bankButton, "LEFT", -2, 0)
    else
        bar:SetPoint("RIGHT", w.sort, "LEFT", -14, 0)
    end
    local free = CreateFrame("Button", nil, w)
    free:SetSize(90, 18)
    free:SetPoint("RIGHT", bar, "LEFT", -6, 0)
    w.free = free:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.free:SetAllPoints(free)
    w.free:SetJustifyH("RIGHT")
    free:SetScript("OnEnter", FreeTip)
    free:SetScript("OnLeave", function() GameTooltip:Hide() end)

    w.search = CreateFrame("EditBox", name .. "Search", w, "SearchBoxTemplate")
    w.search:SetSize(150, 20)
    w.search:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 14, 7)
    w.search:HookScript("OnTextChanged", function() B.Search(this:GetText()) end)
    w.search:SetScript("OnEscapePressed", function() this:SetText(""); this:ClearFocus() end)
    w.money = CreateFrame("Frame", name .. "Money", w, "SmallMoneyFrameTemplate")
    w.money:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 0, 12)
    w.money:EnableMouse(true)
    w.money:SetScript("OnEnter", MoneyTip)
    w.money:SetScript("OnLeave", function() GameTooltip:Hide() end)
    for _, coin in ipairs({ "Gold", "Silver", "Copper" }) do
        local c = _G[name .. "Money" .. coin .. "Button"]
        c:HookScript("OnEnter", MoneyTip)
        c:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return w
end

-- One search for both windows (### C_Container.SetItemSearch).
function B.Search(text)
    C_Container.SetItemSearch(text or "")
    for _, w in ipairs({ B.inventory, B.bank }) do
        if w and w.search:GetText() ~= text then w.search:SetText(text) end
    end
end
