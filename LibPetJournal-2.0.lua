--[[
 Copyright (c) 2012 Robin Schoonover

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to
 deal in the Software without restriction, including without limitation the
 rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 sell copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 IN THE SOFTWARE.
]]

local MAJOR, MINOR = "LibPetJournal-2.0", 6
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

--
-- GLOBALS: PetJournal
--

local _G = _G
local hooksecurefunc, tinsert, pairs, wipe = _G.hooksecurefunc, _G.table.insert, _G.pairs, _G.wipe
local ipairs = _G.ipairs
local C_PetJournal = _G.C_PetJournal

local start_background

--
--
--

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
lib.event_frame = lib.event_frame or CreateFrame("FRAME")
lib.event_frame:SetScript("OnEvent", function(frame, event, ...)
    frame[event](frame, ...)
end)

--
-- filter anti-response
--

local filter_changed = false

lib._antifilter_hooked = lib._antifilter_hooked or {}
lib._antifilter_hook = function()
    filter_changed = true
end

for i,name in ipairs{"SetSearchFilter", "ClearSearchFilter", "SetFlagFilter",
        "SetPetSourceFilter", "SetPetTypeFilter", "AddAllPetSourcesFilter",
        "AddAllPetTypesFilter", "ClearAllPetSourcesFilter", "ClearAllPetTypesFilter",
        "SummonPetByID"} do
    if not lib._antifilter_hooked[name] then
        hooksecurefunc(C_PetJournal, name, function(...)
            return lib._antifilter_hook(name, ...)
        end)
        lib._antifilter_hooked[name] = true
    end
end

--
-- filter handling
--

do
    local PJ_FLAG_FILTERS = {
        [LE_PET_JOURNAL_FLAG_COLLECTED] = true,
        [LE_PET_JOURNAL_FLAG_NOT_COLLECTED] = true,
        [LE_PET_JOURNAL_FLAG_FAVORITES] = false
    }

    local s_search_filter
    local flag_filters = {}
    local type_filters = {}
    local source_filters = {}
    
    lib._filter_hooks = lib._filter_hooks or {}

    -- hook C_PetJournal.SetSearchFilter
    local last_search_filter
    if not lib._filter_hooks.SetSearchFilter then
        hooksecurefunc(C_PetJournal, "SetSearchFilter", function(...)
             lib._filter_hooks.SetSearchFilter(...)
        end)
    end
    lib._filter_hooks.SetSearchFilter = function(str)
        last_search_filter = str
    end
    
    -- hook C_PetJournal.ClearSearchFilter
    if not lib._filter_hooks.ClearSearchFilter then
        hooksecurefunc(C_PetJournal, "ClearSearchFilter", function(...)
             lib._filter_hooks.ClearSearchFilter(...)
        end)
    end
    lib._filter_hooks.ClearSearchFilter = function()
        last_search_filter = nil
    end

    --- Save and clear the PetJournal filters.
    -- Also prevents LibPetJournal or the PetJournal from reacting to filter
    -- events until :RestoreFilters() is called.  This API is called
    -- automatically by LibPetJournal.
    -- @name LibPetJournal:ClearFilters()
    function lib:ClearFilters()
        if PetJournal then
            PetJournal:UnregisterEvent("PET_JOURNAL_LIST_UPDATE")
        end
        lib.event_frame:UnregisterEvent("PET_JOURNAL_LIST_UPDATE")
        
        if last_search_filter ~= "" and last_search_filter ~= nil then
            -- TODO try checking PetJournal's textbox if we get loaded late?
            s_search_filter = last_search_filter
            C_PetJournal.ClearSearchFilter()
        else
            s_search_filter = nil
        end

        for flag, value in pairs(PJ_FLAG_FILTERS) do
            flag_filters[flag] = not C_PetJournal.IsFlagFiltered(flag)
            if flag_filters[flag] ~= value then
                C_PetJournal.SetFlagFilter(flag, value)
            end
        end
        
        local need_add_all = false
        local ntypes = C_PetJournal.GetNumPetTypes()
        for i=1,ntypes do
            type_filters[i] = not C_PetJournal.IsPetTypeFiltered(i)
            if not type_filters[i] then
                need_add_all = true
            end
        end
        if need_add_all then
            C_PetJournal.AddAllPetTypesFilter()
        end
        
        need_add_all = false
        local nsources = C_PetJournal.GetNumPetSources()
        for i=1,nsources do
            source_filters[i] = not C_PetJournal.IsPetSourceFiltered(i)
            if not source_filters[i] then
                need_add_all = true
            end
        end
        if need_add_all then
            C_PetJournal.AddAllPetSourcesFilter()
        end
    end

    --- Restore PetJournal filters after a :ClearFilters() call.
    -- Also reenables PetJournal and LibPetJournal reacting to the updated pet
    -- journal event. until :RestoreFilters() is called.  This API is called
    -- automatically by LibPetJournal.
    -- @name LibPetJournal:RestoreFilters()
    function lib:RestoreFilters()
        if s_search_filter and s_search_filter ~= "" then
            C_PetJournal.SetSearchFilter(s_search_filter)
        end
        
        for flag, value in pairs(flag_filters) do
            if value ~= PJ_FLAG_FILTERS[flag] then
                C_PetJournal.SetFlagFilter(flag, value)
            end
        end
        
        for flag,value in pairs(type_filters) do
            if value ~= true then
                C_PetJournal.SetPetTypeFilter(flag, value)
            end
        end
        
        for flag,value in pairs(source_filters) do
            if value ~= true then
                C_PetJournal.SetPetSourceFilter(flag, value)
            end
        end
    
        if PetJournal then
            PetJournal:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
        end
        lib.event_frame:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    end
end

--
--
--

lib._petids = lib._petids or {}
lib._speciesids = lib._speciesids or {}
lib._set_speciesids = lib._set_speciesids or {}

--- Get an iterator over the list of pet ids.
-- @name LibPetJournal:IteratePetIDs()
function lib:IteratePetIDs(start)
    if start then
        return ipairs(lib._petids), lib._petids, start - 1
    end
    return ipairs(lib._petids)
end
lib.IteratePetIds = lib.IteratePetIDs

--- Get an iterator over the list of species ids.
-- @name LibPetJournal:IterateSpeciesIds()
function lib:IterateSpeciesIDs(start)
    if start then
        return ipairs(lib._speciesids), lib._speciesids, start - 1
    end
    return ipairs(lib._speciesids)
end
lib.IterateSpeciesIds = lib.IterateSpeciesIDs

--- Load pets stored in the PetJournal.
-- Under normal circumstances with API will run on its own in response to
-- updates to the Pet Journal.
-- @name LibPetJournal:LoadPets()
function lib:LoadPets()
    self:ClearFilters()
    
    -- scan pets
    wipe(lib._petids)
    
    local total, owned = C_PetJournal.GetNumPets(false)
    if total == 0 and owned == 0 then
        self.event_frame:Show()
        return
    end
    
    for i = 1,total do
        local petID, speciesID, isOwned = C_PetJournal.GetPetInfoByIndex(i, false)
        
        if isOwned then
            tinsert(lib._petids, petID)
        end
        
        if not lib._set_speciesids[speciesID] then
            lib._set_speciesids[speciesID] = true
            tinsert(lib._speciesids, speciesID)
        end
    end
       
    -- Signal
    self.callbacks:Fire("PetsUpdated", self)
    
    -- restore PJ filters
    self:RestoreFilters()
    
    filter_changed = false
    self.event_frame:Hide()
end

--- Determine if the pet list has been loaded.
-- @name LibPetJournal:IsLoaded()
-- @return boolean indicating whether the pet list has been loaded.
function lib:IsLoaded()
    return #lib._petids > 0 or #lib._speciesids > 0
end

--- Determine how many pets the player owns.
-- @name LibPetJournal:NumPets()
-- @return number of owned pets
function lib:NumPets()
    return #lib._petids
end

lib.event_frame:RegisterEvent("COMPANION_UPDATE")
function lib.event_frame:COMPANION_UPDATE(...)
    local ctype = ...
    -- Usually PET_JOURNAL_LIST_UPDATE is the correct event to watch for, 
    -- but on login, pets are not usually properly loaded yet.  Worse, not 
    -- even at P_E_W will this information be available.  After pets are
    -- loaded, this event only seems to fire when changing pets.
    if (ctype == nil or ctype == "CRITTER") and #lib._petids == 0 then
        lib:LoadPets()
    end
end

lib.event_frame:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
function lib.event_frame:PET_JOURNAL_LIST_UPDATE()
    -- Delay load.  This event will fire multiple times if a 
    -- filter function is called.
    start_background()
end

lib.event_frame:RegisterEvent("ADDON_LOADED")
function lib.event_frame:ADDON_LOADED()
    lib.event_frame:UnregisterEvent("ADDON_LOADED")
    if not lib:IsLoaded() then
        lib:LoadPets()
    end
end

local timer = 0
function start_background()
    timer = 10  -- run immediately on next OnUpdate
    lib.event_frame:Show()
end

lib.event_frame:SetScript("OnUpdate", function(frame, elapsed)
    timer = timer + elapsed
    if timer > 2 then
        if filter_changed then
            filter_changed = false
            if lib:IsLoaded() then
                frame:Hide()
            end
            return
        end
        
        lib:LoadPets()
        timer = 0
    end
end)

