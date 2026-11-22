-- Bags: one window for the bags and one for the bank, in place of the stock ones.
-- Core: the saved table, the stock bag functions taken over, the bank taken over,
-- and the windows that open by themselves. Doc headings: ClassicAPI's docs/API.md.
local _, B = ...
BagsDB = BagsDB or {} -- restored first: LoadSavedVariablesFirst
-- Clear every saved key nothing owns.
for key in pairs(BagsDB) do if key ~= "bagBar" and key ~= "keys" then BagsDB[key] = nil end end
BagsDB.bagBar = type(BagsDB.bagBar) == "table" and BagsDB.bagBar or { inventory = false, bank = true }

-- The first places: bags right, bank left.
B.inventory = B.NewWindow("inventory", "BagsInventory", { 0, 1, 2, 3, 4, -2 }, 1078, 495)
B.bank = B.NewWindow("bank", "BagsBank", { -1, 5, 6, 7, 8, 9, 10 }, 192, 898)
local inventory, bank = B.inventory, B.bank

-- The game's bag keys and buttons open our window for bags 0-4; every other
-- bag keeps the stock function; the key button shows or hides the keys in ours.
local stock = { ToggleBag = ToggleBag, OpenBag = OpenBag, CloseBag = CloseBag }
local function Ours(id) return type(id) == "number" and id >= 0 and id <= 4 end
function ToggleBackpack() inventory:Toggle() end
function OpenBackpack() inventory:Open(true) end -- a merchant or the mailbox: by itself
function CloseBackpack() inventory:Close(true) end
function OpenAllBags(forceOpen) if forceOpen then inventory:Open() else inventory:Toggle() end end
function CloseAllBags() inventory:Hide() end
function ToggleBag(id) if Ours(id) then inventory:Toggle() else return stock.ToggleBag(id) end end
function OpenBag(id) if Ours(id) then inventory:Open(true) else return stock.OpenBag(id) end end
function ToggleKeyRing() BagsDB.keys = not BagsDB.keys; inventory:Open() end -- the stock key button
function CloseBag(id) if Ours(id) then inventory:Close(true) else return stock.CloseBag(id) end end

-- The stock bank frame shows itself on BANKFRAME_OPENED (BankFrame.lua:125): ours does instead.
BankFrame:UnregisterEvent("BANKFRAME_OPENED")

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MAIL_CLOSED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Container.SetItemSearch("") -- a search stays over /reload (### C_Container.SetItemSearch)
    elseif event == "PLAYER_LOGOUT" then
        B.Store.SaveBags()
    elseif event == "BANKFRAME_OPENED" then
        B.atBank = true
        B.Store.SaveBank()
        bank:Open(true, B.Store.Me())
        inventory:Open(true)
    elseif event == "BANKFRAME_CLOSED" then
        B.atBank = nil
        bank:Hide()
        inventory:Close(true)
    elseif event == "AUCTION_HOUSE_SHOW" then
        inventory:Open(true)
    else
        inventory:Close(true) -- the auction house or the mailbox closed
    end
end)
