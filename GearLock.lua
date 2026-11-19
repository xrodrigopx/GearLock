-- GearLock: lock items so they are never sold by accident.
-- If a locked item is sold anyway (right-click, "Sell All Junk", etc.),
-- se recompra automaticamente al instante.

local PREFIX = "|cff33ccffGearLock|r: "
local db
local RefreshBags
local baseline = {}   -- items already in the buyback list when the vendor opens
local attempts = 0

BINDING_HEADER_GEARLOCK = "GearLock"
BINDING_NAME_GEARLOCK_TOGGLE = "Lock / unlock the item under the cursor"

local function Print(msg) print(PREFIX .. msg) end

local function ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

local function ItemLinkByID(id)
  local name, link
  if C_Item and C_Item.GetItemInfo then name, link = C_Item.GetItemInfo(id)
  elseif GetItemInfo then name, link = GetItemInfo(id) end
  return link or ("item:" .. id)
end

---------------------------------------------------------------------------
-- Lock rules
---------------------------------------------------------------------------
local function InEquipmentSet(itemID)
  if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then return false end
  local ok, result = pcall(function()
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
      local ids = C_EquipmentSet.GetItemIDs(setID)
      if ids then
        for _, id in pairs(ids) do
          if id == itemID then return true end
        end
      end
    end
    return false
  end)
  return ok and result
end

local function IsGear(itemID)
  local classID
  if C_Item and C_Item.GetItemInfoInstant then
    classID = select(6, C_Item.GetItemInfoInstant(itemID))
  elseif GetItemInfoInstant then
    classID = select(6, GetItemInfoInstant(itemID))
  end
  if classID ~= 2 and classID ~= 4 then return false end -- 2 = arma, 4 = armadura
  local quality
  if C_Item and C_Item.GetItemQualityByID then quality = C_Item.GetItemQualityByID(itemID) end
  return (quality or 0) >= (db.minQuality or 2)
end

-- Returns the lock reason ("manual", "set", "gear") or nil.
local function ProtectionReason(itemID)
  if not itemID or not db then return nil end
  local manual = db.items[itemID]
  if manual == true then return "manual" end
  if manual == false then return nil end -- excepcion explicita
  if db.protectSets and InEquipmentSet(itemID) then return "set" end
  if db.protectGear and IsGear(itemID) then return "gear" end
  return nil
end

local REASON_TEXT = {
  manual = "locked manually",
  set = "locked (part of an equipment set)",
  gear = "locked (mode: all gear)",
}

local function Toggle(itemID)
  if not itemID then return end
  local link = ItemLinkByID(itemID)
  if ProtectionReason(itemID) then
    db.items[itemID] = nil
    if ProtectionReason(itemID) then
      db.items[itemID] = false -- locked by an automatic rule: create an explicit exception
    end
    Print(link .. " |cffff5555unlocked|r (can be sold).")
  else
    db.items[itemID] = true
    Print(link .. " |cff55ff55locked|r (will not be sold).")
  end
  if RefreshBags then RefreshBags() end
end

---------------------------------------------------------------------------
-- Item under the cursor
---------------------------------------------------------------------------
local function GetHoveredItemID()
  if TooltipUtil and TooltipUtil.GetDisplayedItem then
    local ok, _, link, id = pcall(TooltipUtil.GetDisplayedItem, GameTooltip)
    if ok then
      if id then return id end
      if link then return ItemIDFromLink(link) end
    end
  end
  if GameTooltip and GameTooltip.GetItem then
    local ok, _, link = pcall(GameTooltip.GetItem, GameTooltip)
    if ok and link then return ItemIDFromLink(link) end
  end
end

function GearLock_ToggleHovered()
  local id = GetHoveredItemID()
  if not id then
    Print("Hover an item in your bags and press the key again.")
    return
  end
  Toggle(id)
end

---------------------------------------------------------------------------
-- Visual marker in bags: padlock + grayscale icon
---------------------------------------------------------------------------
local LOCK_TEXTURE = "Interface\\Buttons\\LockButton-Locked-Up"
local lastStats = { path = "-", frames = 0, buttons = 0, locked = 0 }

local function IconOf(button)
  if button.icon then return button.icon end
  if button.Icon then return button.Icon end
  local name = button.GetName and button:GetName()
  return name and _G[name .. "IconTexture"] or nil
end

local function UpdateButton(button)
  local bag = button.GetBagID and button:GetBagID()
  local slot = button.GetID and button:GetID()
  local id = bag and slot and C_Container.GetContainerItemID(bag, slot)
  local show = (id and ProtectionReason(id)) and true or false

  if show and not button.GearLockLock then
    local tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetSize(14, 14)
    tex:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    tex:SetTexture(LOCK_TEXTURE)
    button.GearLockLock = tex
  end
  if button.GearLockLock then button.GearLockLock:SetShown(show) end

  local icon = IconOf(button)
  if icon and icon.SetDesaturated then
    if show then
      icon:SetDesaturated(true)
      button.GearLockGray = true
    elseif button.GearLockGray then
      icon:SetDesaturated(false)
      button.GearLockGray = nil
    end
  end

  -- Alt + click to lock/unlock (hooked once per button)
  if not button.GearLockClickHooked and button.HookScript then
    button.GearLockClickHooked = true
    button:HookScript("OnClick", function(self)
      if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
        local b, sl = self.GetBagID and self:GetBagID(), self:GetID()
        local itemID = b and sl and C_Container.GetContainerItemID(b, sl)
        if itemID then Toggle(itemID) end
      end
    end)
  end

  lastStats.buttons = lastStats.buttons + 1
  if show then lastStats.locked = lastStats.locked + 1 end
end

local function RefreshFrame(frame)
  if not (frame and frame.EnumerateValidItems) then return end
  for _, button in frame:EnumerateValidItems() do
    pcall(UpdateButton, button)
  end
end

local function HookFrame(frame)
  if not frame or frame.GearLockHooked then return end
  frame.GearLockHooked = true
  if frame.UpdateItems then
    hooksecurefunc(frame, "UpdateItems", RefreshFrame)
  end
  frame:HookScript("OnShow", RefreshFrame)
end

-- Plan B: scan all frames looking for bag item buttons.
local function ScanAllFrames()
  local f = EnumerateFrames()
  while f do
    local ok, isItem = pcall(function() return f.GetBagID ~= nil and f.GetID ~= nil and f:IsVisible() end)
    if ok and isItem then pcall(UpdateButton, f) end
    f = EnumerateFrames(f)
  end
end

local refreshQueued = false
local function DoRefresh()
  refreshQueued = false
  if not db then return end
  lastStats = { path = "standard", frames = 0, buttons = 0, locked = 0 }
  local frames = {}
  if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
  if ContainerFrameContainer and ContainerFrameContainer.ContainerFrames then
    for _, fr in ipairs(ContainerFrameContainer.ContainerFrames) do frames[#frames + 1] = fr end
  else
    for i = 1, 13 do
      local fr = _G["ContainerFrame" .. i]
      if fr then frames[#frames + 1] = fr end
    end
  end
  for _, fr in ipairs(frames) do
    HookFrame(fr)
    lastStats.frames = lastStats.frames + 1
    if fr:IsShown() then RefreshFrame(fr) end
  end
  if lastStats.buttons == 0 then
    lastStats.path = "plan B (EnumerateFrames)"
    ScanAllFrames()
  end
end

-- Coalesces several back-to-back requests into a single refresh.
RefreshBags = function()
  if refreshQueued then return end
  refreshQueued = true
  C_Timer.After(0.05, DoRefresh)
end

local function Debug()
  DoRefresh()
  Print(("debug: path=%s, frames=%d, buttons=%d, locked=%d, combined bags=%s")
    :format(lastStats.path, lastStats.frames, lastStats.buttons, lastStats.locked,
            tostring(ContainerFrameCombinedBags ~= nil)))
end

---------------------------------------------------------------------------
-- Automatic buyback of locked items
---------------------------------------------------------------------------
local function NumBuyback()
  if GetNumBuybackItems then return GetNumBuybackItems() end
  if C_MerchantFrame and C_MerchantFrame.GetNumBuybackItems then return C_MerchantFrame.GetNumBuybackItems() end
  return 0
end

local function BuybackID(index)
  if C_MerchantFrame and C_MerchantFrame.GetBuybackItemID then
    local id = C_MerchantFrame.GetBuybackItemID(index)
    if id then return id end
  end
  if GetBuybackItemLink then return ItemIDFromLink(GetBuybackItemLink(index)) end
end

local function BuybackCounts()
  local counts = {}
  for i = 1, NumBuyback() do
    local id = BuybackID(i)
    if id then counts[id] = (counts[id] or 0) + 1 end
  end
  return counts
end

local function CheckBuyback()
  if not (MerchantFrame and MerchantFrame:IsShown()) then return end
  if attempts >= 30 then return end
  local counts = BuybackCounts()
  for i = 1, NumBuyback() do
    local id = BuybackID(i)
    if id and ProtectionReason(id) and (counts[id] or 0) > (baseline[id] or 0) then
      attempts = attempts + 1
      Print("Sold " .. ItemLinkByID(id) .. " (locked): buying it back...")
      BuybackItem(i)
      C_Timer.After(0.4, CheckBuyback)
      return
    end
  end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function HookTooltip()
  if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    pcall(function()
      local reason = data and data.id and ProtectionReason(data.id)
      if reason then
        tooltip:AddLine("|cff55ff55GearLock: " .. REASON_TEXT[reason] .. "|r")
      end
    end)
  end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_UPDATE")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("EQUIPMENT_SETS_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= "GearLock" then return end
    GearLockDB = GearLockDB or {}
    db = GearLockDB
    db.items = db.items or {}
    if db.protectSets == nil then db.protectSets = true end
    if db.protectGear == nil then db.protectGear = false end
    db.minQuality = db.minQuality or 2
    HookTooltip()
    for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "ToggleBag", "OpenBag", "OpenBackpack" }) do
      if _G[fn] then hooksecurefunc(fn, function() C_Timer.After(0.05, RefreshBags) end) end
    end
  elseif event == "MERCHANT_SHOW" then
    attempts = 0
    baseline = BuybackCounts()
  elseif event == "MERCHANT_UPDATE" or event == "BAG_UPDATE_DELAYED" then
    CheckBuyback()
    RefreshBags()
  elseif event == "EQUIPMENT_SETS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    RefreshBags()
  end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function Help()
  Print("commands (/gl or /gearlock):")
  print("  /gl toggle [link]  - lock/unlock the hovered item (or the linked item)")
  print("  /gl list           - list manually locked items")
  print("  /gl sets           - toggle protection for Equipment Manager set items (now: " .. (db.protectSets and "ON" or "OFF") .. ")")
  print("  /gl all            - toggle \"lock all gear\" mode (now: " .. (db.protectGear and "ON" or "OFF") .. ")")
  print("  /gl quality N      - minimum quality for that mode (2 = green, 3 = blue, 4 = epic). Now: " .. db.minQuality)
  print("  /gl debug          - diagnostic info about detected bag slots")
  print("  Alt + click on an item in your bags also locks/unlocks it.")
  print("  You can also bind a key: Options > Keybindings > AddOns > GearLock.")
end

SLASH_GEARLOCK1 = "/gl"
SLASH_GEARLOCK2 = "/gearlock"
SlashCmdList["GEARLOCK"] = function(msg)
  if not db then return end
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()

  if cmd == "toggle" or cmd == "add" or cmd == "lock" then
    local id = ItemIDFromLink(rest) or GetHoveredItemID()
    if not id then Print("Hover an item or paste its link (shift+click)."); return end
    Toggle(id)
  elseif cmd == "list" or cmd == "lista" then
    local n = 0
    for id, v in pairs(db.items) do
      if v == true then n = n + 1; print("  " .. ItemLinkByID(id)) end
    end
    if n == 0 then Print("no manually locked items.") else Print(n .. " locked item(s).") end
  elseif cmd == "debug" then
    Debug()
  elseif cmd == "sets" then
    db.protectSets = not db.protectSets
    Print("lock Equipment Manager set items: " .. (db.protectSets and "|cff55ff55ON|r" or "|cffff5555OFF|r"))
    RefreshBags()
  elseif cmd == "all" or cmd == "gear" or cmd == "todo" then
    db.protectGear = not db.protectGear
    Print("lock all gear (quality >= " .. db.minQuality .. "): " .. (db.protectGear and "|cff55ff55ON|r" or "|cffff5555OFF|r"))
    RefreshBags()
  elseif cmd == "quality" or cmd == "calidad" then
    local q = tonumber(rest)
    if q and q >= 0 and q <= 5 then
      db.minQuality = q
      Print("minimum quality for \"all gear\" mode: " .. q)
      RefreshBags()
    else
      Print("usage: /gl quality N  (2 = green, 3 = blue, 4 = epic)")
    end
  else
    Help()
  end
end
