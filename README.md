# Bags

One window for your bags and one for your bank, in place of the game's own.
For **World of Warcraft 1.12.1** with [ClassicAPI](https://github.com/brues-code/ClassicAPI).

- **One inventory and one bank window.** The bank opens at a banker; both open by themselves at a merchant, the mailbox and the auction house.
- **Search, Sort and a bag bar.** Search dims what does not match. Sort fills your bags (right-click: from the other end). The bag bar puts bags in and takes them out.
- **Slots used** in the header, with each bag's count in its tooltip. The **Keys** button shows your key ring.
- **Quality borders, new-item glow** and **weapon poison badges** with the time or charges left.
- **Your other characters:** read their bags, bank and money with the arrow by the title; item tooltips tell what they carry. Your own bank can be opened anywhere.

## Install

[Download Bags](https://github.com/Fostercare5988/Bags/releases/latest/download/Bags.zip) and extract it into `Interface/AddOns/`, so the folder is `Interface/AddOns/Bags/`. There is nothing to set; open your bags as usual.

## What it calls

ClassicAPI: `C_Container.GetContainerItemInfo`, `GetContainerNumSlots`, `SetItemSearch`, `SortBags`, `SortBankBags` and `Get`/`SetSortBagsRightToLeft`, `BAG_UPDATE_DELAYED` and `INVENTORY_SEARCH_UPDATE`, `C_NewItems`, `C_Item.GetItemTempEnchantInfo`, `GetEnchantInfo` and `GetItemInfo`, `C_Spell.GetSpellTexture`, the Cooldown frame, animation groups, the `OnTooltipSetItem` script with `GameTooltip:GetItem`, the menu dropdown, `C_Timer.After`.

Nothing runs per frame: a closed window listens to nothing, and an open one redraws only the bags that changed.
