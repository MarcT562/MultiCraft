--[[
File : MultiCraft.lua
Author: Ayantir
Version : 3
]]--

-- MultiCraft totally rewrited by Ayantir
-- MultiCraft modified by Darque Flux

local ADDON_NAME = "MultiCraft"

local DEBUG_BASIC = "DEBUG_BASIC";
local DEBUG_TEMP = "DEBUG_TEMP";

-- Inits
local sliderValue = 1
local isWorking = false

-- Tables
local provisioner = {}
local enchanting = {}
local alchemy = {}
local smithing = {}

local selectedCraft = nil 	-- This will hold a pointer to the currently open crafting station
local callDelay = 500
local GENERAL_MODE_CREATION = 1 -- Alchemy, Provisionner
local debugType = {} -- A list of debug types e.g., {DEBUG_BASIC} will enable only basic debug messages, {DEBUG_BASIC, DEBUG_TEMP} will show both of those.
local maxCraftable = 1

-- Will output to chat a debug message if MyPrint is enabled
function MyPrint(message, messageType)
	for _,v in pairs(debugType) do
		if v == messageType then
			d(message)
			break
		end
	end
end

-- Triggers when EVENT_CRAFT_STARTED and Called at Cleanup
local function HideUI()
	-- Hide XML
	MultiCraft:SetHidden(true)
end

local function EnableOrDisableUI()
	
	MyPrint(".EnableOrDisableUI()", DEBUG_BASIC)
	
	-- Init
	local hidden = true
	local mode = selectedCraft:GetMode()
	
	-- Provisioning & Alchemy
	if selectedCraft == provisioner or
	   selectedCraft == alchemy then
		if selectedCraft:IsCraftable() then
			MyPrint(".EnableOrDisableUI->false()", DEBUG_BASIC)
			hidden = false
		end
	-- Enchanting
	elseif selectedCraft == enchanting then
		if (mode == ENCHANTING_MODE_CREATION and selectedCraft:IsCraftable()) or
		   (mode == ENCHANTING_MODE_EXTRACTION and selectedCraft:IsExtractable()) then
			MyPrint(".EnableOrDisableUI->false()", DEBUG_BASIC)
			hidden = false
		end
	-- Smithing (Smithing, Wood, Clothing)
	elseif selectedCraft == smithing then
		-- there is a game bug where this returns erroneously true in refinement after completing an extract that results in having less
		-- than 10 items but still having the item selected
		-- TODO: fix it
		if (mode == SMITHING_MODE_REFINMENT and selectedCraft:IsExtractable()) or
		   --Aya: Buggy with UI_SHORTCUT_SECONDARY, it will bug the UI ->
		   (mode == SMITHING_MODE_CREATION and selectedCraft:IsCraftable()) or
		   (mode == SMITHING_MODE_CREATION and selectedCraft:IsCraftable()) or
		   (mode == SMITHING_MODE_DECONSTRUCTION and selectedCraft:IsDeconstructable()) then
			MyPrint(".EnableOrDisableUI->false()", DEBUG_BASIC)
			hidden = false
		end
	end
	
	-- Alchemy ?
	MyPrint(".EnableOrDisableUI->hidden = " .. tostring(hidden), DEBUG_BASIC)
	
	-- Hide or Show XML
	MultiCraft:SetHidden(hidden)
	
end

-- This function reset the slider to the correct values (min = 1, max = qty craftable, and maybe the default value)
local function ResetSpinner()

	MyPrint(".ResetSpinner()", DEBUG_BASIC)
	
	-- Can really occurs ?
	if not selectedCraft then return end
	
	-- DisableSlider or show ?
	EnableOrDisableUI()
	
	local numCraftable = 1
	-- On which tab are we ? selectedCraft is wrapped by OverrideXXX
	local mode = selectedCraft:GetMode()
	
	-- Get qty craftable
	-- For Provisionner
	if selectedCraft == provisioner then
		if selectedCraft:IsCraftable() then
			local data = PROVISIONER.recipeTree:GetSelectedData()
			numCraftable = data.numCreatable
		else
			-- Only a try to hide when we cannot do anything, need to be reworked, can occurs if we can do 1 food and 0 drink
			numCraftable = 0
		end
	-- For Enchanting
	elseif selectedCraft == enchanting then
		-- 1st tab, making glyphs
		if mode == ENCHANTING_MODE_CREATION then
			if selectedCraft:IsCraftable() then
				-- We look in craftingInventory (Bagpack+Bank) how much items we got, and we select the min, cause enchanting use 1 rune per glyph
				for k, v in pairs(ENCHANTING.runeSlots) do
					if k == 1 then
						numCraftable = v.craftingInventory.itemCounts[v.itemInstanceId]
					else
						numCraftable = zo_min(numCraftable, v.craftingInventory.itemCounts[v.itemInstanceId])
					end
					MyPrint("in for numCraftable = " .. tostring(zo_floor(numCraftable)), DEBUG_BASIC)
				end
			else
				numCraftable = 0
			end
		-- 2nd tab, deconstruct Glyphs
		elseif mode == ENCHANTING_MODE_EXTRACTION then
			if selectedCraft:IsExtractable() then
				-- We count how many Glyphs we got in craftingInventory (Bagpack+Bank)
				numCraftable = ENCHANTING.extractionSlot.craftingInventory.itemCounts[ENCHANTING.extractionSlot.itemInstanceId]
			else
				numCraftable = 0
			end
		end
	-- Alchemy
	elseif selectedCraft == alchemy then
		
		if selectedCraft:IsCraftable() then
			
			-- Same as enchanting, our Qty will be the min between each solvant and reagents
			-- Solvant
			numCraftable = ALCHEMY.solventSlot.craftingInventory.itemCounts[ALCHEMY.solventSlot.itemInstanceId]
			
			if numCraftable then
				-- Reagents
				for k, data in pairs(ALCHEMY.reagentSlots) do
					if data:MeetsUsabilityRequirement() then			
						if data.craftingInventory.itemCounts[data.itemInstanceId] ~= nil then
							numCraftable = zo_min(numCraftable, data.craftingInventory.itemCounts[data.itemInstanceId])
							MyPrint("in for numCraftable = " .. tostring(zo_floor(numCraftable)), DEBUG_BASIC)
						end
					end
				end
			else
				-- No solvants in slot
				numCraftable = 0
			end
		else
			numCraftable = 0
		end
		
	-- Smithing (Wood/Smith/Clothing)
	elseif selectedCraft == smithing then
		-- 1st tab, refinement
		if mode == SMITHING_MODE_REFINMENT then
			-- Count how many Items we got in craftingInventory and divide per stack size needed to refine
			if selectedCraft:IsExtractable() then
				numCraftable = SMITHING.refinementPanel.extractionSlot.craftingInventory.itemCounts[SMITHING.refinementPanel.extractionSlot.itemInstanceId]
				numCraftable = numCraftable / GetRequiredSmithingRefinementStackSize()
			else
				numCraftable = 0
			end
		-- 2nd tab, creation
		elseif mode == SMITHING_MODE_CREATION then
			if selectedCraft:IsCraftable() then
				
				MyPrint("SMITHING Creation", DEBUG_BASIC)
				-- Determine qty to craft
				-- patternIndex is ID of item to do (glove, chest, sword..)
				-- materialIndex is ID of material to use (galatite, iron, etc)
				-- materialQuantity is Qty of material to use (10, 12, etc..)
				-- styleIndex is ID of style to use, qty is always 1
				-- traitIndex is ID of trait to use, qty is always 1
				local patternIndex, materialIndex, materialQuantity, styleIndex, traitIndex = SMITHING.creationPanel:GetAllCraftingParameters()
				
				-- How many material do we got for this item ?
				local materialCount = GetCurrentSmithingMaterialItemCount(patternIndex, materialIndex) / materialQuantity
				-- How many stones ?
				local styleItemCount = GetCurrentSmithingStyleItemCount(styleIndex)
				-- How many trait stones ?
				local traitCount = GetCurrentSmithingTraitItemCount(traitIndex)
				
				-- Because trait is optional, start with the min of material and style which is always needed
				numCraftable = zo_min(materialCount, styleItemCount)
				
				-- A trait has been selected, 1 is No trait, and if no trait min is already known
				if traitIndex ~= 1 then
					-- Protection
					numCraftable = 1
				end
			else
				numCraftable = 0
			end
		-- 3rd tab, deconstruction
		elseif mode == SMITHING_MODE_DECONSTRUCTION then
			if selectedCraft:IsDeconstructable() then
				-- Count how many Items we got in craftingInventory
				numCraftable = SMITHING.deconstructionPanel.extractionSlot.craftingInventory.itemCounts[SMITHING.deconstructionPanel.extractionSlot.itemInstanceId]
			else
				numCraftable = 0
			end
		end
	end
	
	-- Protection against divisions
	numCraftable = zo_floor(numCraftable)
	
	if numCraftable > 0 then
		-- Disable spinner or show ?
		MyPrint(".ResetSpinner->numCraftable = " .. numCraftable, DEBUG_BASIC)
		EnableOrDisableUI()
	end
	
	-- Don't show spinner if Qty = 1
	-- MultiCraft is handled by XML
	if numCraftable <= 1 then
		MyPrint(".ResetSpinner->Hide spinner", DEBUG_BASIC)
		MultiCraft:SetHidden(true)
	else
		MyPrint(".ResetSpinner->Show spinner", DEBUG_BASIC)
		MultiCraft:SetHidden(false)
	end

	maxCraftable = numCraftable
	MyPrint("Max Craftable : " .. maxCraftable, DEBUG_TEMP);
	
	-- User can set its default value instead of 1, TODO, check if default is between MinMax
	if isWorking and sliderValue and sliderValue >= 1 and sliderValue <= maxCraftable then
		MultiCraft:GetNamedChild("Display"):SetText(sliderValue)
	else
		MultiCraft:GetNamedChild("Display"):SetText(1)
	end
	
end

local function canCraft()

	local mode = selectedCraft:GetMode()
	local isAbleToCraft = false;
		
	if selectedCraft == provisioner then
		isAbleToCraft = selectedCraft:IsCraftable();
		if(selectedCraft:IsCraftable()) then
			MyPrint("Provision Is Craftable : Yes", DEBUG_TEMP)
		else
			MyPrint("Provision Is Craftable : No", DEBUG_TEMP)
		end
		
	-- For Enchanting
	elseif selectedCraft == enchanting then
		-- 1st tab, making glyphs
		if mode == ENCHANTING_MODE_CREATION then
			isAbleToCraft = selectedCraft:IsCraftable();
			if(selectedCraft:IsCraftable()) then
				MyPrint("Enchanting Is Craftable : Yes", DEBUG_TEMP)
			else
				MyPrint("Enchanting Is Craftable : No", DEBUG_TEMP)
			end
		-- 2nd tab, deconstruct Glyphs
		elseif mode == ENCHANTING_MODE_EXTRACTION then
			isAbleToCraft = selectedCraft:IsExtractable();
			if(selectedCraft:IsExtractable()) then
				MyPrint("Enchanting Is Extractable : Yes", DEBUG_TEMP)
			else
				MyPrint("Enchanting Is Extractable : No", DEBUG_TEMP)
			end
		end
		
	-- Alchemy
	elseif selectedCraft == alchemy then
		isAbleToCraft = selectedCraft:IsCraftable();
		if(selectedCraft:IsCraftable()) then
			MyPrint("Alchemy Is Craftable : Yes", DEBUG_TEMP)
		else
			MyPrint("Alchemy Is Craftable : No", DEBUG_TEMP)
		end
		
	-- Smithing (Wood/Smith/Clothing)
	elseif selectedCraft == smithing then
		-- 1st tab, refinement
		
		if mode == SMITHING_MODE_REFINMENT then
			isAbleToCraft = selectedCraft:IsExtractable();
			if(selectedCraft:IsExtractable()) then
				MyPrint("Smithing Is Extractable : Yes", DEBUG_TEMP)
			else
				MyPrint("Smithing Is Extractable : No", DEBUG_TEMP)
			end
		-- 2nd tab, creation
		elseif mode == SMITHING_MODE_CREATION then
			isAbleToCraft = selectedCraft:IsCraftable();
			if(selectedCraft:IsCraftable()) then
				MyPrint("Smithing Creation Is Craftable : Yes", DEBUG_TEMP)
			else
				MyPrint("Smithing Creation Is Craftable : No", DEBUG_TEMP)
			end
		-- 3rd tab, deconstruction
		elseif mode == SMITHING_MODE_DECONSTRUCTION then
			isAbleToCraft = selectedCraft:IsDeconstructable();
			if(selectedCraft:IsDeconstructable()) then
				MyPrint("Smithing Is Deconstructable : Yes", DEBUG_TEMP)
			else
				MyPrint("Smithing Is Deconstructable : No", DEBUG_TEMP)
			end
		end
	end
	if(isAbleToCraft == true) then
		MyPrint("Can Craft - Yes", DEBUG_TEMP)
	else
		MyPrint("Can Craft - No", DEBUG_TEMP)
	end
	return isAbleToCraft;
end

-- Triggers when EVENT_CRAFTING_STATION_INTERACT
local function SelectCraftingSkill(eventCode, craftingType)
	
	MyPrint("SelectCraftingSkill", DEBUG_BASIC)
	
	-- Provisionner
	if craftingType == CRAFTING_TYPE_PROVISIONING then
		selectedCraft = provisioner
		MyPrint(".SelectCraftingSkill->CRAFTING_TYPE_PROVISIONING", DEBUG_BASIC)
	-- Enchanting
	elseif craftingType == CRAFTING_TYPE_ENCHANTING then
		selectedCraft = enchanting
		MyPrint(".SelectCraftingSkill->CRAFTING_TYPE_ENCHANTING", DEBUG_BASIC)
		-- ResetSpinner() is called by OnSlotChanged
	-- Alchemy
	elseif craftingType == CRAFTING_TYPE_ALCHEMY then
		selectedCraft = alchemy
		MyPrint(".SelectCraftingSkill->CRAFTING_TYPE_ALCHEMY", DEBUG_BASIC)
		-- Init Slider
		ResetSpinner()
	-- Blacksmithing
	elseif craftingType == CRAFTING_TYPE_BLACKSMITHING then
		selectedCraft = smithing
		MyPrint(".SelectCraftingSkill->CRAFTING_TYPE_BLACKSMITHING", DEBUG_BASIC)
		-- ResetSpinner() is called by OnSelectedPatternChanged 
	-- Clothier
	elseif craftingType == CRAFTING_TYPE_CLOTHIER then
		selectedCraft = smithing
		MyPrint(".SelectCraftingSkill->CRAFTING_TYPE_CLOTHIER", DEBUG_BASIC)
	-- Woodworking
	elseif craftingType == CRAFTING_TYPE_WOODWORKING then
		selectedCraft = smithing
		MyPrint(".SelectCraftingSkill->CRAFTING_TYPE_WOODWORKING", DEBUG_BASIC)
	end
	
	-- Prevent UI bug due to fast Esc
	CALLBACK_MANAGER:FireCallbacks("CraftingAnimationsStopped")
	
end

-- Triggers when EVENT_END_CRAFTING_STATION_INTERACT
local function Cleanup()
	
	-- Hide UI
	MyPrint(".Cleanup", DEBUG_BASIC)
	
	-- Remove button
	
	HideUI()
	isWorking = false
	selectedCraft = nil
	
	MyPrint(".Cleanup->Cleaned", DEBUG_BASIC)

end

-- Executed when EVENT_CRAFT_COMPLETED is triggered, set just before craft has been started
local function ContinueWork(workFunc)
	
	MyPrint(".ContinueWork", DEBUG_BASIC)
	
	-- Need to do somework ?
	MyPrint("Slider Value : " .. sliderValue .. " - Max Craftable : " .. maxCraftable, DEBUG_TEMP);
	if sliderValue > 1 and (canCraft() == true) then
	
		-- Let's do another one
		sliderValue = sliderValue - 1
		
		MyPrint("Multicraft will craft : " .. sliderValue, DEBUG_BASIC)
		MyPrint("ContinueWork.In.sliderValue " .. sliderValue, DEBUG_BASIC)
		
		-- It will call itself with a delay of XX ms
		zo_callLater(workFunc, callDelay)
		
	else
		
		MyPrint(".ContinueWork->finished", DEBUG_BASIC)
		
		-- Work is finished, unregisters itselfs
		EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_CRAFT_COMPLETED)
		
		-- Reset slider to 1, and change work flag
		isWorking = false
		ResetSpinner()
		
	end
	
end

-- Executed when user start to craft (press the keybind)
-- Only for : PROVISIONER:Create(), ENCHANTING:Create(), ALCHEMY:Create(), SMITHING.creationPanel:Create(), SMITHING.deconstructionPanel:Extract(), SMITHING.refinementPanel:Extract()
-- When this function is executed, result is always a success, qties and skill have already been verified
local function Work(workFunc)
	
	MyPrint(".Work", DEBUG_BASIC)
	
	-- selectedCraft is set when entering the craft station, isWorking is for prevent MultiCraft loops, this function is called only at 1st launch
	if selectedCraft and not isWorking then
	
		if MultiCraft:IsHidden() == false then
			
			-- Handle values typed by hand
			MultiCraft_ChangeQty(0)
			
			MyPrint("Craft will work 1 item in few ms", DEBUG_BASIC)
			MyPrint(".Work:sliderValuee->" .. sliderValue, DEBUG_BASIC)
			
			if sliderValue > 1 and sliderValue <= maxCraftable then
			
				-- We're working
				isWorking = true
				
				-- When a craft is completed, execute :ContinueWork to find if we need to continue work
				EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_CRAFT_COMPLETED, function() ContinueWork(workFunc) end)
			
			else
				MyPrint(".Work:sliderValue->" .. sliderValue, DEBUG_BASIC)
				ResetSpinner()
				
				-- If user set value to 0, craft will be done and sliderValue set to 1. But if we still can craft more than 1 craft, UI should be displayed again after craft
				EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_CRAFT_COMPLETED, function() ContinueWork(workFunc) end)
				
			end
			
		end
		
	end
	
end

local function OverrideProvisionner()

	-- Provisioner
	provisioner.RefreshRecipeList = PROVISIONER.RefreshRecipeList
	PROVISIONER.RefreshRecipeList = function(...)
		provisioner.RefreshRecipeList(...)
		MyPrint("RefreshRecipeList->ResetSpinner", DEBUG_BASIC)
		ResetSpinner()
	end
	
	provisioner.SelectNode = PROVISIONER.recipeTree.SelectNode
	PROVISIONER.recipeTree.SelectNode = function(...)
		provisioner.SelectNode(...)
		MyPrint("SelectNode->ResetSpinner", DEBUG_BASIC)
		ResetSpinner()
	end
	
	-- Create function
	provisioner.Create = function()
		PROVISIONER:Create()
	end
	
	provisioner.GetMode = function()
		return GENERAL_MODE_CREATION
	end
	
	-- Wrapper to check if an item is craftable
	provisioner.IsCraftable = function()
		return PROVISIONER:IsCraftable()
	end
	
	-- wrapper to get the keybind descriptor for the craft button
	-- Aya: 1.5 dropped KeybindStripDescriptor for PROVISIONER: Replaced by mainKeybindStripDescriptor
	--provisioner.GetSecondaryKeybindStripDescriptor = function()
	--	return PROVISIONER.mainKeybindStripDescriptor[1]
	--end

end

local function OverrideEnchanting()

	-- Enchanting
	-- Tab change
	enchanting.SetEnchantingMode = ENCHANTING.SetEnchantingMode
	
	ENCHANTING.SetEnchantingMode = function(...)
		enchanting.SetEnchantingMode(...)
	end
	
	-- For polymorphism
	enchanting.GetMode = function()
		return ENCHANTING:GetEnchantingMode()
	end
	
	-- Rune slot change
	enchanting.SetRuneSlotItem = ENCHANTING.SetRuneSlotItem
	
	ENCHANTING.SetRuneSlotItem = function(...)
		enchanting.SetRuneSlotItem(...)
		-- Reset Slider each time a Runeslot is changed
		MyPrint("SetRuneSlotItem->ResetSpinner", DEBUG_BASIC)
		ResetSpinner()
	end
	
	-- Extraction selection change
	enchanting.OnSlotChanged = ENCHANTING.OnSlotChanged
	
	ENCHANTING.OnSlotChanged = function(...)
		enchanting.OnSlotChanged(...)
		-- Reset Slider each time Glyph is changed
		MyPrint("OnSlotChanged->ResetSpinner", DEBUG_BASIC)
		ResetSpinner()
	end
	
	-- Create and extract function
	enchanting.Create = function()
		ENCHANTING:Create()
	end
	
	-- wrapper to check if an item is craftable
	enchanting.IsCraftable = function()
		return ENCHANTING:IsCraftable()
	end
	
	-- ?
	enchanting.IsExtractable = enchanting.IsCraftable
	
	-- Wrapper to get the keybind descriptor for the craft button
	--enchanting.GetSecondaryKeybindStripDescriptor = function()
	--	return ENCHANTING.keybindStripDescriptor[2]
	--end

end

local function OverrideAlchemy()

	-- Alchemy
	-- Selection Change
	alchemy.OnSlotChanged = ALCHEMY.OnSlotChanged
	ALCHEMY.OnSlotChanged = function(...)
		alchemy.OnSlotChanged(...)
		-- Reset slider each time a solvant or a plant is changed
		MyPrint("OnSlotChanged->ResetSpinner", DEBUG_BASIC)
		ResetSpinner()
	end
	
	-- Create function
	alchemy.Create = function()
		ALCHEMY:Create()
	end
	
	-- For polymorphism
	alchemy.GetMode = function()
		return GENERAL_MODE_CREATION
	end
	
	-- Wrapper to check if an item is craftable
	alchemy.IsCraftable = function()
		return ALCHEMY:IsCraftable()
	end
	
end

function OverrideSmithing()

	-- Smithing
	-- tab change
	
	smithing.SetMode = SMITHING.SetMode
	SMITHING.SetMode = function(...)
		smithing.SetMode(...)
		ResetSpinner()
	end
	
	smithing.GetMode = function()
		return SMITHING.mode
	end
	
	-- Pattern selection in creation
	smithing.OnSelectedPatternChanged = SMITHING.OnSelectedPatternChanged
	SMITHING.OnSelectedPatternChanged = function(...)
		smithing.OnSelectedPatternChanged(...)
		MyPrint("OnSelectedPatternChanged->ResetSpinner", DEBUG_BASIC)
		ResetSpinner()
	end
	
	-- Item selection in deconstruction
	smithing.OnExtractionSlotChanged = SMITHING.OnExtractionSlotChanged
	SMITHING.OnExtractionSlotChanged = function(...)
		smithing.OnExtractionSlotChanged(...)
		MyPrint("OnExtractionSlotChanged->ResetSpinner", DEBUG_BASIC)
		ResetSpinner()
	end
		
	-- Create function
	smithing.Create = function()
		SMITHING.creationPanel:Create()
	end
			
	-- Wrapper to check if an item is craftable
	smithing.IsCraftable = function()
		return SMITHING.creationPanel:IsCraftable()
	end
		
	-- Deconstruction extract function
	smithing.Deconstruct = function()
		SMITHING.deconstructionPanel:Extract()
	end
	
	-- Wrapper to check if an item is deconstructable
	smithing.IsDeconstructable = function()
		return SMITHING.deconstructionPanel:IsExtractable()
	end
	
	-- Refinement extract function
	smithing.Extract = function()
		SMITHING.refinementPanel:Extract()
	end
	
	-- Wrapper to check if an item is refinable
	smithing.IsExtractable = function()
		return SMITHING.refinementPanel:IsExtractable()
	end

end

local function onAddonLoaded(_, addonName)
	
	-- Protect
	if addonName == ADDON_NAME then
	
		-- Set up function overrides
		OverrideProvisionner()
		OverrideEnchanting()
		OverrideAlchemy()
		OverrideSmithing()
		
		-- Hook everything up
		-- Will Hook Real function with MultiCraft ones (MultiCraft function will be executed before real ones)
		ZO_PreHook(PROVISIONER, 'Create', function() Work(provisioner.Create) end)
		ZO_PreHook(ENCHANTING, 'Create', function() Work(enchanting.Create) end)
		ZO_PreHook(ALCHEMY, 'Create', function() Work(alchemy.Create) end)
		ZO_PreHook(SMITHING.creationPanel, 'Create', function() Work(smithing.Create) end)
		ZO_PreHook(SMITHING.deconstructionPanel, 'Extract', function() Work(smithing.Deconstruct) end)
		ZO_PreHook(SMITHING.refinementPanel, 'Extract', function() Work(smithing.Extract) end)
		
		-- Register events
		-- Show UI and set it if needed (slider, #number of crafts)
		EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_CRAFTING_STATION_INTERACT, SelectCraftingSkill)
		-- Hide UI while crafting
		EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_CRAFT_STARTED, HideUI)
		-- Restore UID when leaving craft station
		EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_END_CRAFTING_STATION_INTERACT, Cleanup)
		
		EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)
		
	end
	
end

-- Called by UI
function MultiCraft_ChangeQty(delta)
	
	MyPrint("MultiCraft_ChangeQty", DEBUG_BASIC)
	
	local displayedValue = MultiCraft:GetNamedChild("Display"):GetText()
	
	if displayedValue ~= "" then
		local value = tonumber(displayedValue)
		value = value + delta
		
		if value < 1 then value = 1 end
		if value > maxCraftable then value = maxCraftable end
		
		MultiCraft:GetNamedChild("Display"):SetText(value)
		sliderValue = value
		
	else
		MultiCraft:GetNamedChild("Display"):SetText(1)
		sliderValue = 1
	end
	
	MyPrint("MultiCraft_ChangeQty->" .. sliderValue, DEBUG_BASIC)

end

-- Initialize Addon
EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, onAddonLoaded)