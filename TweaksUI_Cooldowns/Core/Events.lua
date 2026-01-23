-- TweaksUI: Cooldowns - Events
-- Custom event system for inter-module communication

local ADDON_NAME, TUICD = ...

TUICD.Events = {}
local Events = TUICD.Events

-- Registered callbacks
local callbacks = {}

-- Register a callback for an event
function Events:Register(event, callback, owner)
    if not callbacks[event] then
        callbacks[event] = {}
    end
    
    table.insert(callbacks[event], {
        callback = callback,
        owner = owner,
    })
end

-- Unregister callbacks for an owner
function Events:UnregisterAll(owner)
    for event, eventCallbacks in pairs(callbacks) do
        for i = #eventCallbacks, 1, -1 do
            if eventCallbacks[i].owner == owner then
                table.remove(eventCallbacks, i)
            end
        end
    end
end

-- Fire an event
function Events:Fire(event, ...)
    if not callbacks[event] then
        return
    end
    
    for _, cb in ipairs(callbacks[event]) do
        local success, err = pcall(cb.callback, ...)
        if not success then
            TUICD:PrintError("Event callback error for " .. event .. ": " .. tostring(err))
        end
    end
end

-- WoW Event frame for Blizzard events
local eventFrame = CreateFrame("Frame")
local blizzardCallbacks = {}

-- Register for a Blizzard event
function Events:RegisterBlizzard(event, callback, owner)
    if not blizzardCallbacks[event] then
        blizzardCallbacks[event] = {}
        eventFrame:RegisterEvent(event)
    end
    
    table.insert(blizzardCallbacks[event], {
        callback = callback,
        owner = owner,
    })
end

-- Unregister Blizzard event callbacks for an owner
function Events:UnregisterBlizzardAll(owner)
    for event, eventCallbacks in pairs(blizzardCallbacks) do
        for i = #eventCallbacks, 1, -1 do
            if eventCallbacks[i].owner == owner then
                table.remove(eventCallbacks, i)
            end
        end
        
        -- If no more callbacks for this event, unregister
        if #eventCallbacks == 0 then
            eventFrame:UnregisterEvent(event)
            blizzardCallbacks[event] = nil
        end
    end
end

-- Handle Blizzard events
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not blizzardCallbacks[event] then
        return
    end
    
    for _, cb in ipairs(blizzardCallbacks[event]) do
        local success, err = pcall(cb.callback, event, ...)
        if not success then
            TUICD:PrintError("Blizzard event callback error for " .. event .. ": " .. tostring(err))
        end
    end
end)
