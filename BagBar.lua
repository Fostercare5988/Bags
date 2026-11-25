-- Bags: the bag icons of a window, behind its "Bags" button: put a bag in, take it
-- out, point at one to light up its slots. The bank's row also buys bag slots.
local _, B = ...
local Store = B.Store
local EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local function Slot(icon) return ContainerIDToInventoryID(icon:GetID()) end
local function Live(icon) return icon.window:Live() end

local function OnClick() if Live(this) then PutItemInBag(Slot(this)) end end
local function OnDrag() if Live(this) then PickupBagFromSlot(Slot(this)) end end
local function OnEnter()
    local icon, holder = this, this.window.holders[this:GetID()]
    GameTooltip:SetOwner(icon, B.Side(icon))
    if icon.link then
        GameTooltip:SetHyperlink(icon.link)
    elseif not Live(icon) or not GameTooltip:SetInventoryItem("player", Slot(icon)) then
        GameTooltip:SetText(icon.buy and BANK_BAG_PURCHASE or EQUIP_CONTAINER)
    end
    GameTooltip:Show()
    for slot = 1, holder.size or 0 do holder.buttons[slot]:LockHighlight() end
end
local function OnLeave()
    GameTooltip:Hide()
    local holder = this.window.holders[this:GetID()]
    for slot = 1, holder.size or 0 do holder.buttons[slot]:UnlockHighlight() end
end

local function Buy()
    BankFrame.nextSlotCost = GetBankSlotCost((GetNumBankSlots())) -- the stock dialog shows it
    StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
end
local function BuyTip()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(BANKSLOTPURCHASE)
    SetTooltipMoney(GameTooltip, GetBankSlotCost((GetNumBankSlots())))
    GameTooltip:Show()
end

local function Make(w)
    w.bar = CreateFrame("Frame", nil, w)
    w.bar:SetSize(1, 32)
    w.bar:SetPoint("TOPLEFT", w, "TOPLEFT", 8, -30)
    w.icons = {}
    for i, bag in ipairs(w.bags) do
        if bag > 0 then
            local name = w:GetName() .. "Bag" .. bag
            local icon = CreateFrame("Button", name, w.bar, "ItemButtonTemplate")
            icon:SetID(bag)
            icon:SetScale(0.8)
            icon:SetPoint("TOPLEFT", w.bar, "TOPLEFT", (#w.icons) * 42, 0)
            icon.window, icon.texture = w, _G[name .. "IconTexture"]
            icon:RegisterForDrag("LeftButton")
            icon:SetScript("OnClick", OnClick)
            icon:SetScript("OnReceiveDrag", OnClick)
            icon:SetScript("OnDragStart", OnDrag)
            icon:SetScript("OnEnter", OnEnter)
            icon:SetScript("OnLeave", OnLeave)
            w.icons[#w.icons + 1] = icon
        end
    end
    if w.kind == "bank" then
        w.buy = CreateFrame("Button", nil, w.bar, "UIPanelButtonTemplate")
        w.buy:SetSize(70, 20)
        w.buy:SetPoint("LEFT", w.icons[#w.icons], "RIGHT", 8, 0)
        w.buy:SetText("Buy slot")
        w.buy:SetScript("OnClick", Buy)
        w.buy:SetScript("OnEnter", BuyTip)
        w.buy:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

-- Draw the bag icons of the shown character: live ones from your slots, stored ones from the record.
function B.BagBar(w)
    local shown = BagsDB.bagBar[w.kind]
    if not w.bar then
        if not shown then return end
        Make(w)
    end
    w.bar:SetShown(shown)
    if not shown then return end
    local live, owner = w:Live(), w:Owner()
    local slots, full = 0, true
    if w.kind == "bank" and live then slots, full = GetNumBankSlots() end
    for _, icon in ipairs(w.icons) do
        local texture
        icon.link = not live and Store.Link(owner, icon:GetID()) or nil
        icon.buy = w.kind == "bank" and live and icon:GetID() - 4 > slots
        if icon.link then
            texture = select(10, C_Item.GetItemInfo(icon.link))
        elseif live then
            texture = GetInventoryItemTexture("player", Slot(icon))
        end
        icon.texture:SetTexture(texture or EMPTY)
        icon.texture:SetDesaturated(live and IsInventoryItemLocked(Slot(icon)) and 1 or nil)
        if icon.buy then icon.texture:SetVertexColor(1, 0.1, 0.1) else icon.texture:SetVertexColor(1, 1, 1) end
    end
    if w.buy then w.buy:SetShown(live and not full) end
end
