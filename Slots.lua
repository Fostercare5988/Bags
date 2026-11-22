-- Bags: the item slots of both windows, made on first need. A live slot is read
-- with one C_Container.GetContainerItemInfo call into one buffer; a stored slot
-- comes from the record (Store.lua). Doc headings are ClassicAPI's docs/API.md.
local _, B = ...
local Store = B.Store

local info, where, made = {}, {}, 0 -- the one item buffer and item location
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Uncommon to legendary.
local QUALITY = { [2] = { 0.05, 1, 0.15 }, [3] = { 0, 0.7, 1 }, [4] = { 0.85, 0.2, 1 }, [5] = { 1, 0.55, 0 } }
local EDGE = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 }

-- GAP: the icon of a temporary enchant. C_Item.GetEnchantInfo gives a name and a
-- proc spell, no icon or item (### C_Item.GetEnchantInfo); a DLL could give the item.
local icons = {}
local function EnchantIcon(id)
    if not icons[id] then
        local e = C_Item.GetEnchantInfo(id)
        icons[id] = e and e.spellID and C_Spell.GetSpellTexture(e.spellID) or QUESTION
    end
    return icons[id]
end

-- Search, lock and a cooldown waiting to start, in that order of strength.
local function Shade(b)
    local grey = b.filtered and 0.3 or b.locked and 0.5 or b.waiting and 0.4 or 1
    b.icon:SetDesaturated((b.filtered or b.locked) and 1 or nil)
    b.icon:SetVertexColor(grey, grey, grey)
    b.edge:SetAlpha(b.filtered and 0.25 or 1)
end

local function Cooldown(b)
    local start, duration, enable = 0, 0, 1
    if b.hasItem and not b.stored then start, duration, enable = GetContainerItemCooldown(b.bag, b:GetID()) end
    b.waiting = duration > 0 and enable == 0
    if start > 0 and duration > 0 and enable > 0 then
        if b.cdStart ~= start then b.cooldown:SetCooldown(start, duration); b.cdStart = start end
    elseif b.cdStart then
        b.cooldown:Clear(); b.cdStart = nil
    end
end

local function Glow(b)
    if b.new and not b.glow then
        local g = b:CreateTexture(nil, "OVERLAY")
        g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        g:SetBlendMode("ADD")
        g:SetSize(66, 66)
        g:SetPoint("CENTER", b, "CENTER", 0, 0)
        g:SetVertexColor(1, 0.85, 0.3)
        g.pulse = g:CreateAnimationGroup() -- played by the engine: no OnUpdate (### AnimationGroup)
        g.pulse:SetLooping("BOUNCE")
        local fade = g.pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1); fade:SetToAlpha(0.3); fade:SetDuration(0.8)
        b.glow = g
    end
    if b.new then
        b.glow:Show()
        if not b.glow.pulse:IsPlaying() then b.glow.pulse:Play() end
    elseif b.glow and b.glow:IsShown() then
        b.glow.pulse:Stop(); b.glow:Hide()
    end
end

local function NewBadge(b)
    local badge = CreateFrame("Frame", nil, b)
    badge:SetSize(14, 14)
    badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetAllPoints(badge)
    badge.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    badge.text = badge:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    badge.text:SetPoint("TOPRIGHT", badge, "BOTTOMRIGHT", 0, -1)
    badge.text:SetTextColor(1, 0.4, 0.1)
    -- The time left counts down by itself: a Cooldown with no swipe and no flash.
    local timer = CreateFrame("Cooldown", nil, badge)
    timer:SetSize(30, 10)
    timer:SetPoint("TOPRIGHT", badge, "BOTTOMRIGHT", 0, -1)
    timer:SetDrawSwipe(false); timer:SetDrawBling(false)
    timer:SetCountdownAbbrevThreshold(60)
    timer:GetCountdownFontString():SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    timer:SetScript("OnCooldownDone", function() B.Enchant(b) end) -- the enchant ran out
    badge.timer, b.badge = timer, badge
    return badge
end

-- The poison or oil on a weapon in your bags: its icon, and the time or the charges left.
function B.Enchant(b)
    local has, ms, charges, id
    if b.hasItem and not b.stored and b.bag >= 0 and b.bag <= 4 then
        where.bagID, where.slotIndex = b.bag, b:GetID()
        has, ms, charges, id = C_Item.GetItemTempEnchantInfo(where)
    end
    local badge = b.badge
    if not has then
        if badge and badge:IsShown() then badge.timer:Clear(); badge.ends = nil; badge:Hide() end
        return
    end
    badge = badge or NewBadge(b)
    if badge.id ~= id then badge.icon:SetTexture(EnchantIcon(id)); badge.id = id end
    local few = charges and charges > 0 and charges <= 5
    badge.text:SetText(few and charges .. "c" or "")
    if few or ms <= 0 then
        badge.timer:Clear(); badge.ends = nil
    else
        local ends = GetTime() + ms / 1000 -- started once: reading the same enchant again keeps it
        if not badge.ends or math.abs(badge.ends - ends) > 1.5 then
            badge.ends = ends
            badge.timer:SetCooldown(GetTime(), ms / 1000)
        end
    end
    badge:Show()
end

local function Show(b, texture, count, quality)
    b.icon:SetTexture(texture)
    b.count = count or 0 -- the stock stack split reads it
    if b.count > 1 then b.countText:SetText(b.count > 999 and "*" or b.count); b.countText:Show() else b.countText:Hide() end
    local c = QUALITY[quality]
    if c then b.edge:SetBackdropBorderColor(c[1], c[2], c[3]); b.edge:Show() else b.edge:Hide() end
end

-- A full redraw, or only the lock, search and new marks ("light"), or the cooldown ("cool").
function B.Draw(b, owner, what)
    if owner then
        b.stored, b.locked, b.filtered, b.new = true, nil, nil, nil
        local link, count = Store.Slot(owner, b.bag, b:GetID())
        local _, quality, texture
        if link then _, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(link) end
        if link and not texture then b.window.missing = true end
        b.link, b.hasItem = link, link and 1
        Show(b, link and (texture or QUESTION), count, quality)
    elseif what == "cool" then
        if b.hasItem then Cooldown(b); Shade(b) end
        return
    else
        b.stored, b.link = nil, nil
        local item = C_Container.GetContainerItemInfo(b.bag, b:GetID(), info)
        b.locked, b.filtered = item and item.isLocked, item and item.isFiltered
        b.new = item and b.bag >= 0 and b.bag <= 4 and C_NewItems.IsNewItem(b.bag, b:GetID())
        if what == "light" then Glow(b); Shade(b); return end
        b.hasItem, b.readable = item and 1, item and item.isReadable
        if item and not (item.iconFileID and item.quality) then b.window.missing = true end
        Show(b, item and (item.iconFileID or QUESTION), item and item.stackCount, item and item.quality)
    end
    Cooldown(b); B.Enchant(b); Glow(b); Shade(b)
end

-- The tooltip on the side away from the screen's edge, as the stock slots do.
function B.Side(f) return (f:GetRight() or 0) >= GetScreenWidth() / 2 and "ANCHOR_LEFT" or "ANCHOR_RIGHT" end

local function OnEnter()
    local b = this
    if b.stored then
        if b.link then GameTooltip:SetOwner(b, B.Side(b)); GameTooltip:SetHyperlink(b.link); GameTooltip:Show() end
    elseif b.bag == -1 then
        GameTooltip:SetOwner(b, B.Side(b))
        GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(b:GetID()))
    else
        ContainerFrameItemButton_OnEnter(b)
    end
    if b.new then C_NewItems.RemoveNewItem(b.bag, b:GetID()); b.new = nil; Glow(b) end
end
local function OnLeave() GameTooltip:Hide(); ResetCursor() end

-- A live slot is the stock one: the global is looked up at each click, since Mail
-- and shootyepgp replace ContainerFrameItemButton_OnClick after we load.
local function OnClick()
    local b = this
    if not b.stored then return ContainerFrameItemButton_OnClick(arg1) end
    if arg1 ~= "LeftButton" or not b.link then return end
    if IsControlKeyDown() then
        DressUpItemLink(b.link)
    elseif IsShiftKeyDown() and ChatFrameEditBox:IsShown() then
        local _, link = C_Item.GetItemInfo(b.link) -- its colour and name, with the stored enchant and suffix
        if link then ChatFrameEditBox:Insert((string.gsub(link, "item:[%-%d:]+", b.link, 1))) end
    end
end
local function OnDrag() if not this.stored then ContainerFrameItemButton_OnClick("LeftButton", 1) end end
local function OnHide() if this.hasStackSplit == 1 then StackSplitFrame:Hide() end end

function B.Button(holder, slot)
    local b = holder.buttons[slot]
    if b then return b end
    made = made + 1
    local name = "BagsItem" .. made
    b = CreateFrame("Button", name, holder, "ItemButtonTemplate") -- no OnUpdate, unlike the stock slot
    b:SetID(slot)
    b.bag, b.window = holder:GetID(), holder:GetParent()
    b.icon, b.countText = _G[name .. "IconTexture"], _G[name .. "Count"]
    b.cooldown = CreateFrame("Cooldown", nil, b)
    b.cooldown:SetAllPoints(b)
    b.edge = CreateFrame("Frame", nil, b)
    b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.edge:SetBackdrop(EDGE)
    b.edge:Hide()
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("OnDragStart", OnDrag)
    b:SetScript("OnReceiveDrag", OnDrag)
    b:SetScript("OnHide", OnHide)
    holder.buttons[slot] = b
    return b
end
