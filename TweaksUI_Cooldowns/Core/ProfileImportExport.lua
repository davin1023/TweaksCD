-- TUICD Profile Import/Export
-- TUI150: format with delta encoding and optional compression (1.5.0+)
-- Also supports importing TUICD: Cooldowns (TUI:CD) profiles

local ADDON_NAME, TUICD = ...

TUICD.ProfileImportExport = {}
local PIE = TUICD.ProfileImportExport

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local EXPORT_VERSION = "150"  -- 1.5.0
local EXPORT_PREFIX = "TUI" .. EXPORT_VERSION .. ":"

-- TUI:CD import support
local TUICD_PREFIX = "!TUICD1!"

-- ============================================================================
-- SERIALIZATION (JSON-like format)
-- ============================================================================

local function SerializeValue(val, depth)
    depth = depth or 0
    if depth > 50 then return "null" end  -- Prevent infinite recursion
    
    local t = type(val)
    if t == "string" then
        -- Escape special characters
        local escaped = val:gsub("\\", "\\\\")
                           :gsub("\"", "\\\"")
                           :gsub("\n", "\\n")
                           :gsub("\r", "\\r")
                           :gsub("\t", "\\t")
        return "\"" .. escaped .. "\""
    elseif t == "number" then
        -- Handle special float values
        if val ~= val then return "null" end  -- NaN
        if val == math.huge then return "999999999" end
        if val == -math.huge then return "-999999999" end
        return tostring(val)
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "table" then
        -- Check if it's an array (sequential numeric keys starting at 1)
        local isArray = true
        local maxIndex = 0
        local count = 0
        for k, v in pairs(val) do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                isArray = false
                break
            end
            maxIndex = math.max(maxIndex, k)
        end
        -- Also verify no gaps
        if isArray and maxIndex ~= count then
            isArray = false
        end
        
        local parts = {}
        if isArray and maxIndex > 0 then
            -- Serialize as array
            for i = 1, maxIndex do
                table.insert(parts, SerializeValue(val[i], depth + 1))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- Serialize as object (sort keys for consistent output)
            local keys = {}
            for k in pairs(val) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
            
            for _, k in ipairs(keys) do
                local keyStr = SerializeValue(tostring(k), depth + 1)
                local valStr = SerializeValue(val[k], depth + 1)
                table.insert(parts, keyStr .. ":" .. valStr)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

local function DeserializeValue(str, pos)
    pos = pos or 1
    
    -- Skip whitespace
    while pos <= #str and str:sub(pos, pos):match("%s") do
        pos = pos + 1
    end
    
    if pos > #str then return nil, pos end
    
    local char = str:sub(pos, pos)
    
    -- String
    if char == '"' then
        local result = ""
        local i = pos + 1
        while i <= #str do
            local c = str:sub(i, i)
            if c == "\\" and i < #str then
                local next = str:sub(i + 1, i + 1)
                if next == "\\" then
                    result = result .. "\\"
                elseif next == '"' then
                    result = result .. '"'
                elseif next == "n" then
                    result = result .. "\n"
                elseif next == "r" then
                    result = result .. "\r"
                elseif next == "t" then
                    result = result .. "\t"
                else
                    result = result .. next
                end
                i = i + 2
            elseif c == '"' then
                return result, i + 1
            else
                result = result .. c
                i = i + 1
            end
        end
        return nil, pos  -- Unterminated string
    end
    
    -- Number
    if char:match("[%-0-9]") then
        local numStr = str:match("^%-?[0-9]+%.?[0-9]*[eE]?[%-+]?[0-9]*", pos)
        if numStr then
            local num = tonumber(numStr)
            if num then
                return num, pos + #numStr
            end
        end
    end
    
    -- Boolean/null
    if str:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif str:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif str:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    end
    
    -- Array
    if char == "[" then
        local result = {}
        pos = pos + 1
        while pos <= #str do
            -- Skip whitespace
            while pos <= #str and str:sub(pos, pos):match("%s") do
                pos = pos + 1
            end
            if str:sub(pos, pos) == "]" then
                return result, pos + 1
            end
            
            local val, newPos = DeserializeValue(str, pos)
            if newPos == pos then break end
            table.insert(result, val)
            pos = newPos
            
            -- Skip whitespace and comma
            while pos <= #str and (str:sub(pos, pos):match("%s") or str:sub(pos, pos) == ",") do
                pos = pos + 1
            end
        end
        return result, pos
    end
    
    -- Object
    if char == "{" then
        local result = {}
        pos = pos + 1
        while pos <= #str do
            -- Skip whitespace
            while pos <= #str and str:sub(pos, pos):match("%s") do
                pos = pos + 1
            end
            if str:sub(pos, pos) == "}" then
                return result, pos + 1
            end
            
            -- Parse key
            local key, newPos = DeserializeValue(str, pos)
            if not key then break end
            pos = newPos
            
            -- Skip colon and whitespace
            while pos <= #str and (str:sub(pos, pos):match("%s") or str:sub(pos, pos) == ":") do
                pos = pos + 1
            end
            
            -- Parse value
            local val
            val, pos = DeserializeValue(str, pos)
            
            -- Convert numeric string keys back to numbers
            -- (handles sparse arrays that were serialized as objects)
            if type(key) == "string" then
                local numKey = tonumber(key)
                if numKey and tostring(numKey) == key then
                    key = numKey
                end
            end
            
            result[key] = val
            
            -- Skip whitespace and comma
            while pos <= #str and (str:sub(pos, pos):match("%s") or str:sub(pos, pos) == ",") do
                pos = pos + 1
            end
        end
        return result, pos
    end
    
    return nil, pos
end

-- ============================================================================
-- DELTA ENCODING
-- ============================================================================

-- Deep copy utility
local function DeepCopy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        copy[DeepCopy(k)] = DeepCopy(v)
    end
    return copy
end

-- Encode only values that differ from defaults (recursive)
function PIE:DeltaEncode(settings, defaults)
    if type(settings) ~= "table" then
        return settings
    end
    
    defaults = defaults or {}
    local delta = {}
    local hasContent = false
    
    for key, value in pairs(settings) do
        local defaultValue = defaults[key]
        
        if type(value) == "table" and type(defaultValue) == "table" then
            -- Recurse into nested tables
            local subDelta = self:DeltaEncode(value, defaultValue)
            if subDelta and next(subDelta) then
                delta[key] = subDelta
                hasContent = true
            end
        elseif value ~= defaultValue then
            -- Value differs from default, include it
            if type(value) == "table" then
                delta[key] = DeepCopy(value)
            else
                delta[key] = value
            end
            hasContent = true
        end
    end
    
    return hasContent and delta or nil
end

-- Decode delta back to full settings by merging with defaults
function PIE:DeltaDecode(delta, defaults)
    if not delta then
        return DeepCopy(defaults)
    end
    
    local settings = DeepCopy(defaults or {})
    
    for key, value in pairs(delta) do
        if type(value) == "table" and type(settings[key]) == "table" then
            -- Recurse into nested tables
            settings[key] = self:DeltaDecode(value, settings[key])
        else
            -- Direct value
            if type(value) == "table" then
                settings[key] = DeepCopy(value)
            else
                settings[key] = value
            end
        end
    end
    
    return settings
end

-- ============================================================================
-- COMPRESSION (uses LibDeflate if available)
-- ============================================================================

local function GetLibDeflate()
    if LibStub then
        return LibStub:GetLibrary("LibDeflate", true)
    end
    return nil
end

function PIE:Compress(str)
    local LibDeflate = GetLibDeflate()
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(str)
        if compressed then
            return LibDeflate:EncodeForPrint(compressed), true
        end
    end
    -- Fallback: just base64-like encode to make it safe for clipboard
    return str, false
end

function PIE:Decompress(str, wasCompressed)
    local LibDeflate = GetLibDeflate()
    if LibDeflate and wasCompressed then
        local decoded = LibDeflate:DecodeForPrint(str)
        if decoded then
            local decompressed = LibDeflate:DecompressDeflate(decoded)
            if decompressed then
                return decompressed
            end
        end
    end
    -- Return as-is if not compressed or decompression fails
    return str
end

-- ============================================================================
-- CHECKSUM
-- ============================================================================

local function CalculateChecksum(str)
    local sum = 0
    for i = 1, #str do
        sum = (sum * 31 + string.byte(str, i)) % 2147483647
    end
    -- Convert to base36 for shorter representation
    local chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local result = ""
    while sum > 0 do
        local remainder = sum % 36
        result = chars:sub(remainder + 1, remainder + 1) .. result
        sum = math.floor(sum / 36)
    end
    return result == "" and "0" or result
end

-- ============================================================================
-- PRE-EXPORT SYNC
-- ============================================================================

-- Ensure all modules have synced their in-memory settings to the database
-- This is critical because some modules keep settings in memory and only persist periodically
function PIE:SyncAllModulesToDatabase()
    -- Helper to sync a module - calls SaveSettings if available, then GetSettings
    local function SyncModule(moduleId)
        local moduleObj = TUICD.ModuleManager and TUICD.ModuleManager:GetModule(moduleId)
        if moduleObj then
            -- First, call SaveSettings if the module has it (flushes in-memory state)
            if moduleObj.SaveSettings then
                pcall(function() moduleObj:SaveSettings() end)
            end
            
            -- Then get settings and ensure they're in the database
            if moduleObj.GetSettings then
                local success, settings = pcall(function() return moduleObj:GetSettings() end)
                if success and settings and type(settings) == "table" then
                    -- Explicitly save to database
                    if TUICD.Database and TUICD.Database.SetModuleSettings then
                        TUICD.Database:SetModuleSettings(moduleId, settings)
                    end
                end
            end
        end
    end
    
    -- Sync each module using their module IDs
    SyncModule("cooldowns")
    SyncModule("unitFrames")
    SyncModule("chat")
    SyncModule("castBars")
    SyncModule("nameplates")
    SyncModule("personalResources")
    SyncModule("actionBars")
    SyncModule("general")
    SyncModule("layout")
    
    -- IMPORTANT: Save snap attachments to layout settings before export
    -- These are stored separately in SnapLocking and need to be persisted
    if TUICD.SnapLocking and TUICD.SnapLocking.SaveAttachments then
        TUICD.SnapLocking:SaveAttachments()
    end
    
    -- Save ActionBar container positions (they use their own save mechanism)
    if TUICD.ActionBarContainers and TUICD.ActionBarContainers.SaveAllPositions then
        pcall(function() TUICD.ActionBarContainers:SaveAllPositions() end)
    end
    
    -- Save UI Frame container positions
    if TUICD.UIFrameContainers and TUICD.UIFrameContainers.SaveAllPositions then
        pcall(function() TUICD.UIFrameContainers:SaveAllPositions() end)
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

-- Export options:
--   modules = { "cooldowns", "unitFrames", ... } or nil for all
--   includeLayout = true/false
--   includeEnabled = true/false
--   useDeltaEncoding = true/false (default true)
function PIE:Export(options)
    options = options or {}
    
    if not TweaksUI_Cooldowns_CharDB then
        return nil, "No settings to export"
    end
    
    -- IMPORTANT: Sync all modules' in-memory settings to database before export
    -- Some modules (like Cooldowns) keep settings in memory and only persist periodically
    self:SyncAllModulesToDatabase()
    
    -- Get screen info for resolution-independent exports
    local screenWidth, screenHeight = GetPhysicalScreenSize()
    local uiScale = UIParent:GetEffectiveScale()
    
    local exportData = {
        _meta = {
            version = EXPORT_VERSION,
            addon = "TUICD",
            created = time(),
            charName = UnitName("player"),
            realm = GetRealmName(),
            -- Resolution info for scale adjustment on import
            screenWidth = screenWidth,
            screenHeight = screenHeight,
            uiScale = uiScale,
        },
        modules = {},
    }
    
    -- Determine which modules to export
    local modulesToExport = options.modules
    if not modulesToExport then
        -- Export all modules with settings
        modulesToExport = {}
        if TweaksUI_Cooldowns_CharDB.settings then
            for moduleId in pairs(TweaksUI_Cooldowns_CharDB.settings) do
                table.insert(modulesToExport, moduleId)
            end
        end
    end
    
    -- Get defaults for delta encoding
    local useDeltas = options.useDeltaEncoding ~= false
    
    -- Export each module's settings
    for _, moduleId in ipairs(modulesToExport) do
        local settings = TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings[moduleId]
        if settings then
            -- For layout module, just copy as-is (no CENTER_REL conversion)
            -- The BOTTOMLEFT absolute positions are more reliable than converted coordinates
            -- Resolution adjustment can be applied separately if needed
            if moduleId == "layout" then
                local exportSettings = DeepCopy(settings)
                
                if useDeltas then
                    local config = TUICD.Presets and TUICD.Presets:GetModuleConfig(moduleId)
                    local defaults = config and config.defaults or {}
                    local delta = self:DeltaEncode(exportSettings, defaults)
                    if delta then
                        exportData.modules[moduleId] = delta
                    else
                        -- No delta means everything is default, but still export for layout
                        exportData.modules[moduleId] = exportSettings
                    end
                else
                    exportData.modules[moduleId] = exportSettings
                end
            elseif useDeltas then
                -- Try to get defaults from preset registry
                local config = TUICD.Presets and TUICD.Presets:GetModuleConfig(moduleId)
                local defaults = config and config.defaults or {}
                
                -- If defaults are empty, try to get them directly from the module
                if not next(defaults) then
                    local moduleObj = TUICD.ModuleManager and TUICD.ModuleManager:GetModule(moduleId)
                    if moduleObj and moduleObj.GetDefaults then
                        defaults = moduleObj:GetDefaults() or {}
                    end
                end
                
                -- If we still have no defaults, export the full settings (no delta)
                -- This ensures we don't lose data for modules without GetDefaults
                if not next(defaults) then
                    exportData.modules[moduleId] = DeepCopy(settings)
                else
                    local delta = self:DeltaEncode(settings, defaults)
                    if delta then
                        exportData.modules[moduleId] = delta
                    end
                end
            else
                exportData.modules[moduleId] = DeepCopy(settings)
            end
        end
    end
    
    -- NOTE: Layout positions and snap attachments are exported as part of modules.layout
    -- (they are stored in TweaksUI_Cooldowns_CharDB.settings.layout)
    
    -- Include module enabled states if requested
    if options.includeEnabled ~= false and TweaksUI_Cooldowns_CharDB.modules then
        exportData.enabled = DeepCopy(TweaksUI_Cooldowns_CharDB.modules)
    end
    
    -- Include container positions (UI Frame and Action Bar containers)
    -- These are per-character settings that should be part of profiles
    if options.includeLayout ~= false then
        if TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions then
            exportData.uiFrameContainerPositions = DeepCopy(TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions)
        end
        if TweaksUI_Cooldowns_CharDB.actionBarContainerPositions then
            exportData.actionBarContainerPositions = DeepCopy(TweaksUI_Cooldowns_CharDB.actionBarContainerPositions)
        end
    end
    
    -- Include cooldowns custom entries if cooldowns module is being exported
    if options.modules then
        for _, moduleId in ipairs(options.modules) do
            if moduleId == "cooldowns" then
                if TweaksUI_Cooldowns_CharDB.cooldowns then
                    -- Only export customEntries, not trackerCache (it's regenerated)
                    exportData.cooldowns = {
                        customEntries = DeepCopy(TweaksUI_Cooldowns_CharDB.cooldowns.customEntries or {})
                    }
                end
                -- Per-Icon highlight settings (all tracker types)
                if TweaksUI_Cooldowns_CharDB.buffHighlights then
                    exportData.buffHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.buffHighlights)
                end
                if TweaksUI_Cooldowns_CharDB.essentialHighlights then
                    exportData.essentialHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.essentialHighlights)
                end
                if TweaksUI_Cooldowns_CharDB.utilityHighlights then
                    exportData.utilityHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.utilityHighlights)
                end
                if TweaksUI_Cooldowns_CharDB.customHighlights then
                    exportData.customHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.customHighlights)
                end
                -- MultiTracker system (Custom Trackers including Essential/Utility from CDM)
                if TweaksUI_Cooldowns_CharDB.multiTrackers then
                    exportData.multiTrackers = DeepCopy(TweaksUI_Cooldowns_CharDB.multiTrackers)
                end
                -- Per-Icon highlights for multiCustom trackers (keyed by dbKey like multiCustom1Highlights)
                local multiCustomHighlights = {}
                for dbKey, dbData in pairs(TweaksUI_Cooldowns_CharDB) do
                    if type(dbKey) == "string" and dbKey:match("^multiCustom%d+Highlights$") then
                        multiCustomHighlights[dbKey] = DeepCopy(dbData)
                    end
                end
                if next(multiCustomHighlights) then
                    exportData.multiCustomHighlights = multiCustomHighlights
                end
                -- Docks settings (Dynamic Docks feature)
                if TweaksUI_Cooldowns_CharDB.docks then
                    exportData.docks = DeepCopy(TweaksUI_Cooldowns_CharDB.docks)
                end
                break
            end
        end
    elseif not options.modules then
        -- Exporting all - include cooldowns data
        if TweaksUI_Cooldowns_CharDB.cooldowns then
            exportData.cooldowns = {
                customEntries = DeepCopy(TweaksUI_Cooldowns_CharDB.cooldowns.customEntries or {})
            }
        end
        -- Per-Icon highlight settings (all tracker types)
        if TweaksUI_Cooldowns_CharDB.buffHighlights then
            exportData.buffHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.buffHighlights)
        end
        if TweaksUI_Cooldowns_CharDB.essentialHighlights then
            exportData.essentialHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.essentialHighlights)
        end
        if TweaksUI_Cooldowns_CharDB.utilityHighlights then
            exportData.utilityHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.utilityHighlights)
        end
        if TweaksUI_Cooldowns_CharDB.customHighlights then
            exportData.customHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.customHighlights)
        end
        -- MultiTracker system (Custom Trackers including Essential/Utility from CDM)
        if TweaksUI_Cooldowns_CharDB.multiTrackers then
            exportData.multiTrackers = DeepCopy(TweaksUI_Cooldowns_CharDB.multiTrackers)
        end
        -- Per-Icon highlights for multiCustom trackers (keyed by dbKey like multiCustom1Highlights)
        local multiCustomHighlights = {}
        for dbKey, dbData in pairs(TweaksUI_Cooldowns_CharDB) do
            if type(dbKey) == "string" and dbKey:match("^multiCustom%d+Highlights$") then
                multiCustomHighlights[dbKey] = DeepCopy(dbData)
            end
        end
        if next(multiCustomHighlights) then
            exportData.multiCustomHighlights = multiCustomHighlights
        end
        -- Docks settings (Dynamic Docks feature)
        if TweaksUI_Cooldowns_CharDB.docks then
            exportData.docks = DeepCopy(TweaksUI_Cooldowns_CharDB.docks)
        end
    end
    
    -- Mark if delta encoding was used
    exportData._meta.deltaEncoded = useDeltas
    
    -- Serialize
    local serialized = SerializeValue(exportData)
    if not serialized then
        return nil, "Serialization failed"
    end
    
    -- Compress
    local compressed, wasCompressed = self:Compress(serialized)
    
    -- Add checksum to metadata
    local checksum = CalculateChecksum(serialized)
    
    -- Build final string: TUI150:C{checksum}:{data}
    -- C = compressed, U = uncompressed
    local prefix = EXPORT_PREFIX .. (wasCompressed and "C" or "U") .. checksum .. ":"
    
    return prefix .. compressed
end

-- ============================================================================
-- TUI:CD IMPORT SUPPORT
-- ============================================================================

-- Deserialize TUI:CD Lua table format (different from TUI's JSON-like format)
local function DeserializeTUICDTable(str)
    if type(str) ~= "string" then
        return nil, "Invalid input"
    end
    
    -- Safely load the string as a Lua chunk
    local func, err = loadstring("return " .. str)
    if not func then
        return nil, err
    end
    
    -- Execute in a sandboxed environment
    local env = {}
    setfenv(func, env)
    
    local success, result = pcall(func)
    if not success then
        return nil, result
    end
    
    return result
end

-- Check if a string is a TUI:CD import
function PIE:IsTUICDImport(encodedString)
    return encodedString and encodedString:match("^" .. TUICD_PREFIX)
end

-- Parse and validate a TUI:CD import string
function PIE:ValidateTUICDImport(encodedString)
    if not encodedString or type(encodedString) ~= "string" then
        return false, "Invalid input"
    end
    
    -- Check prefix
    if not encodedString:match("^" .. TUICD_PREFIX) then
        return false, "Not a TUI:CD import string"
    end
    
    -- Get data after prefix
    local encoded = encodedString:gsub("^" .. TUICD_PREFIX, "")
    
    -- Get LibDeflate
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not LibDeflate then
        return false, "LibDeflate not available"
    end
    
    -- Decode
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return false, "Failed to decode import string"
    end
    
    -- Decompress
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Failed to decompress import string"
    end
    
    -- Deserialize (TUI:CD uses Lua table literal format)
    local importData, err = DeserializeTUICDTable(serialized)
    if not importData then
        return false, "Failed to deserialize: " .. (err or "unknown error")
    end
    
    -- Validate structure
    if importData.addon ~= "TweaksUI_Cooldowns" then
        return false, "This is not a TUICD: Cooldowns profile"
    end
    
    if not importData.profile then
        return false, "Missing profile data"
    end
    
    -- Return parsed data for inspection
    return true, {
        version = importData.version,
        exportedAt = importData.exportedAt,
        isTUICDImport = true,
        _parsed = importData,
    }
end

-- Convert TUI:CD profile format to TUI profile format
function PIE:ConvertTUICDToTUI(tuicdData)
    local profile = tuicdData.profile
    if not profile then
        return nil, "No profile data found"
    end
    
    -- Build TUI-compatible profile structure
    local tuiProfile = {
        version = TUICD.VERSION,
        created = time(),
        modified = time(),
        importedFrom = {
            source = "TweaksUI_Cooldowns",
            version = tuicdData.version,
            date = tuicdData.exportedAt,
        },
        -- Only cooldowns module settings
        modules = {
            cooldowns = profile.trackers or {},
        },
        -- Module enabled state (cooldowns enabled since we're importing CD settings)
        enabled = {
            cooldowns = true,
        },
        -- Custom entries
        cooldowns = {
            customEntries = profile.customEntries or {},
        },
        -- Highlight settings (same structure in both addons)
        buffHighlights = profile.buffHighlights or {},
        essentialHighlights = profile.essentialHighlights or {},
        utilityHighlights = profile.utilityHighlights or {},
        customHighlights = profile.customHighlights or {},
        -- Docks settings
        docks = profile.docks or {},
    }
    
    return tuiProfile
end

-- ============================================================================
-- IMPORT
-- ============================================================================

-- Validate an import string without applying it
function PIE:Validate(encodedString)
    if not encodedString or type(encodedString) ~= "string" then
        return false, "Invalid input"
    end
    
    -- Check for TUI:CD import first
    if self:IsTUICDImport(encodedString) then
        return self:ValidateTUICDImport(encodedString)
    end
    
    -- Check prefix
    if not encodedString:match("^TUI%d%d%d:") then
        -- Check for old format
        if encodedString:match("^TUI1:") then
            return false, "Old format (pre-1.5.0) - not supported"
        end
        return false, "Invalid format: expected 'TUI###:' prefix or '!TUICD1!' prefix"
    end
    
    -- Parse header: TUI150:C{checksum}:{data}
    local version, compressFlag, checksum, data = encodedString:match("^TUI(%d%d%d):([CU])([A-Z0-9]+):(.+)$")
    
    if not version then
        return false, "Invalid header format"
    end
    
    if version ~= EXPORT_VERSION then
        return false, "Unsupported version: " .. version
    end
    
    -- Decompress if needed
    local wasCompressed = (compressFlag == "C")
    local decompressed = self:Decompress(data, wasCompressed)
    
    if not decompressed then
        return false, "Decompression failed"
    end
    
    -- Verify checksum
    local actualChecksum = CalculateChecksum(decompressed)
    if actualChecksum ~= checksum then
        return false, "Checksum mismatch - data may be corrupted"
    end
    
    -- Parse the data
    local parsed, _ = DeserializeValue(decompressed, 1)
    if not parsed then
        return false, "Failed to parse data"
    end
    
    -- Validate structure
    if not parsed._meta then
        return false, "Missing metadata"
    end
    
    -- Return parsed data for inspection
    return true, {
        version = parsed._meta.version,
        created = parsed._meta.created,
        charName = parsed._meta.charName,
        realm = parsed._meta.realm,
        deltaEncoded = parsed._meta.deltaEncoded,
        modules = parsed.modules and self:GetTableKeys(parsed.modules) or {},
        hasLayout = parsed.layout ~= nil,
        hasEnabled = parsed.enabled ~= nil,
        _parsed = parsed,  -- Store for import
    }
end

-- Helper to get keys from a table
function PIE:GetTableKeys(tbl)
    local keys = {}
    if tbl then
        for k in pairs(tbl) do
            table.insert(keys, k)
        end
        table.sort(keys)
    end
    return keys
end

-- Import and create a new profile
function PIE:Import(encodedString, profileName)
    -- Validate first
    local valid, info = self:Validate(encodedString)
    if not valid then
        return false, info  -- info is error message
    end
    
    if not profileName or profileName == "" then
        return false, "Profile name is required"
    end
    
    -- Check if profile already exists
    if TUICD.Profiles and TUICD.Profiles:ProfileExists(profileName) then
        return false, "A profile with that name already exists"
    end
    
    -- Handle TUI:CD imports
    if info.isTUICDImport then
        local tuiProfile, err = self:ConvertTUICDToTUI(info._parsed)
        if not tuiProfile then
            return false, err or "Failed to convert TUI:CD profile"
        end
        
        -- Create the profile
        if not TweaksUI_Cooldowns_DB then TweaksUI_Cooldowns_DB = {} end
        if not TweaksUI_Cooldowns_DB.profiles then TweaksUI_Cooldowns_DB.profiles = {} end
        
        TweaksUI_Cooldowns_DB.profiles[profileName] = tuiProfile
        
        TUICD:Print("Imported TUI:CD profile: |cff00ff00" .. profileName .. "|r")
        TUICD:Print("|cff888888(Cooldowns settings only - from TUICD: Cooldowns)|r")
        
        return true, {
            profileName = profileName,
            modulesImported = {"cooldowns"},
            isTUICDImport = true,
            hasLayout = false,
            hasEnabled = true,
            hasCooldowns = tuiProfile.cooldowns ~= nil,
            hasBuffHighlights = tuiProfile.buffHighlights ~= nil,
            hasEssentialHighlights = tuiProfile.essentialHighlights ~= nil,
            hasUtilityHighlights = tuiProfile.utilityHighlights ~= nil,
            hasCustomHighlights = tuiProfile.customHighlights ~= nil,
            hasDocks = tuiProfile.docks ~= nil,
        }
    end
    
    -- Standard TUI import
    local parsed = info._parsed
    
    -- Decode deltas if needed
    local fullModules = {}
    if parsed._meta.deltaEncoded and parsed.modules then
        for moduleId, moduleData in pairs(parsed.modules) do
            -- Get defaults from preset registry first
            local config = TUICD.Presets and TUICD.Presets:GetModuleConfig(moduleId)
            local defaults = config and config.defaults or {}
            
            -- If defaults are empty, try to get them directly from the module
            if not next(defaults) then
                local moduleObj = TUICD.ModuleManager and TUICD.ModuleManager:GetModule(moduleId)
                if moduleObj and moduleObj.GetDefaults then
                    defaults = moduleObj:GetDefaults() or {}
                end
            end
            
            -- If we have no defaults, the exported data is already full (not delta)
            -- Just use it as-is
            if not next(defaults) then
                fullModules[moduleId] = DeepCopy(moduleData)
            else
                fullModules[moduleId] = self:DeltaDecode(moduleData, defaults)
            end
        end
    else
        fullModules = parsed.modules or {}
    end
    
    -- Create the profile
    if not TweaksUI_Cooldowns_DB then TweaksUI_Cooldowns_DB = {} end
    if not TweaksUI_Cooldowns_DB.profiles then TweaksUI_Cooldowns_DB.profiles = {} end
    
    TweaksUI_Cooldowns_DB.profiles[profileName] = {
        version = parsed._meta.version,
        created = time(),
        modified = time(),
        importedFrom = {
            charName = parsed._meta.charName,
            realm = parsed._meta.realm,
            date = parsed._meta.created,
            -- Store source resolution for scale adjustment when loading
            screenWidth = parsed._meta.screenWidth,
            screenHeight = parsed._meta.screenHeight,
            uiScale = parsed._meta.uiScale,
        },
        modules = fullModules,
        enabled = parsed.enabled or {},
        -- Container positions
        uiFrameContainerPositions = parsed.uiFrameContainerPositions or {},
        actionBarContainerPositions = parsed.actionBarContainerPositions or {},
        -- Cooldowns and per-icon highlight settings
        cooldowns = parsed.cooldowns or {},
        buffHighlights = parsed.buffHighlights or {},
        essentialHighlights = parsed.essentialHighlights or {},
        utilityHighlights = parsed.utilityHighlights or {},
        customHighlights = parsed.customHighlights or {},
        -- MultiTracker system (Custom Trackers including Essential/Utility from CDM)
        multiTrackers = parsed.multiTrackers or {},
        -- Per-Icon highlights for multiCustom trackers
        multiCustomHighlights = parsed.multiCustomHighlights or {},
        -- Docks settings (Dynamic Docks feature)
        docks = parsed.docks or {},
    }
    
    TUICD:Print("Imported profile: |cff00ff00" .. profileName .. "|r")
    
    -- Check if layout data exists in modules (new format)
    local hasLayoutData = fullModules.layout ~= nil
    
    return true, {
        profileName = profileName,
        modulesImported = self:GetTableKeys(fullModules),
        hasLayout = hasLayoutData,
        hasEnabled = parsed.enabled ~= nil,
        hasCooldowns = parsed.cooldowns ~= nil,
        hasBuffHighlights = parsed.buffHighlights ~= nil,
        hasEssentialHighlights = parsed.essentialHighlights ~= nil,
        hasUtilityHighlights = parsed.utilityHighlights ~= nil,
        hasCustomHighlights = parsed.customHighlights ~= nil,
        hasMultiTrackers = parsed.multiTrackers ~= nil,
        hasMultiCustomHighlights = parsed.multiCustomHighlights ~= nil,
        hasDocks = parsed.docks ~= nil,
    }
end

-- ============================================================================
-- QUICK EXPORT HELPERS
-- ============================================================================

-- Export all settings
function PIE:ExportAll()
    return self:Export({
        includeLayout = true,
        includeEnabled = true,
        useDeltaEncoding = true,
    })
end

-- Export specific modules only
function PIE:ExportModules(moduleIds)
    return self:Export({
        modules = moduleIds,
        includeLayout = false,
        includeEnabled = false,
        useDeltaEncoding = true,
    })
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function PIE:Initialize()
    TUICD:PrintDebug("ProfileImportExport system initialized")
end

-- ============================================================================
-- DEBUG: Profile Data Dump
-- ============================================================================

function PIE:DumpPositionData()
    print("|cff00ff00=== TUICD Position Data Dump ===|r")
    
    -- 1. Layout element positions
    print("|cffFFFF00Layout Element Positions:|r")
    if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.layout and TweaksUI_Cooldowns_CharDB.settings.layout.elements then
        local count = 0
        for id, pos in pairs(TweaksUI_Cooldowns_CharDB.settings.layout.elements) do
            count = count + 1
            print(string.format("  %s: point=%s x=%.1f y=%.1f", 
                id, pos.point or "nil", pos.x or 0, pos.y or 0))
        end
        print(string.format("  Total: %d elements", count))
    else
        print("  (none)")
    end
    
    -- 2. Layout attachments
    print("|cffFFFF00Layout Attachments:|r")
    if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.layout and TweaksUI_Cooldowns_CharDB.settings.layout.attachments then
        local count = 0
        for childId, att in pairs(TweaksUI_Cooldowns_CharDB.settings.layout.attachments) do
            count = count + 1
            print(string.format("  %s -> %s", childId, att.parentId or "nil"))
        end
        print(string.format("  Total: %d attachments", count))
    else
        print("  (none)")
    end
    
    -- 3. Container positions
    print("|cffFFFF00ActionBar Container Positions:|r")
    if TweaksUI_Cooldowns_CharDB.actionBarContainerPositions then
        for key, pos in pairs(TweaksUI_Cooldowns_CharDB.actionBarContainerPositions) do
            print(string.format("  %s: point=%s x=%.1f y=%.1f", 
                key, pos.point or "nil", pos.x or 0, pos.y or 0))
        end
    else
        print("  (none)")
    end
    
    print("|cffFFFF00UI Frame Container Positions:|r")
    if TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions then
        for key, pos in pairs(TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions) do
            print(string.format("  %s: point=%s x=%.1f y=%.1f", 
                key, pos.point or "nil", pos.x or 0, pos.y or 0))
        end
    else
        print("  (none)")
    end
    
    -- 4. PersonalResources positions
    print("|cffFFFF00PersonalResources Positions:|r")
    if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.personalResources then
        local pr = TweaksUI_Cooldowns_CharDB.settings.personalResources
        if pr.healthBar then
            print(string.format("  healthBar: x=%.1f y=%.1f anchor=%s", 
                pr.healthBar.positionX or 0, pr.healthBar.positionY or 0, pr.healthBar.anchor or "nil"))
        end
        if pr.powerBar then
            print(string.format("  powerBar: x=%.1f y=%.1f anchor=%s", 
                pr.powerBar.positionX or 0, pr.powerBar.positionY or 0, pr.powerBar.anchor or "nil"))
        end
        if pr.classPower then
            print(string.format("  classPower: x=%.1f y=%.1f anchor=%s", 
                pr.classPower.positionX or 0, pr.classPower.positionY or 0, pr.classPower.anchor or "nil"))
        end
    else
        print("  (none)")
    end
    
    -- 5. Cooldowns tracker positions
    print("|cffFFFF00Cooldowns Tracker Positions:|r")
    if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.cooldowns then
        local cd = TweaksUI_Cooldowns_CharDB.settings.cooldowns
        if cd.customTrackers then
            print(string.format("  customTrackers: point=%s x=%.1f y=%.1f", 
                cd.customTrackers.point or "nil", cd.customTrackers.x or 0, cd.customTrackers.y or 0))
        end
    else
        print("  (none)")
    end
    
    -- 6. ActionBars positions
    print("|cffFFFF00ActionBars Positions:|r")
    if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.actionBars then
        local ab = TweaksUI_Cooldowns_CharDB.settings.actionBars
        if ab.bars then
            for barId, barSettings in pairs(ab.bars) do
                if barSettings.x or barSettings.y then
                    print(string.format("  %s: x=%.1f y=%.1f", 
                        barId, barSettings.x or 0, barSettings.y or 0))
                end
            end
        end
        if ab.systemBars then
            for barId, barSettings in pairs(ab.systemBars) do
                if barSettings.x or barSettings.y then
                    print(string.format("  %s: x=%.1f y=%.1f", 
                        barId, barSettings.x or 0, barSettings.y or 0))
                end
            end
        end
    else
        print("  (none)")
    end
    
    print("|cff00ff00=== End Position Data Dump ===|r")
end

-- Slash command for debugging
SLASH_TUIDUMP1 = "/tuidump"
SlashCmdList["TUIDUMP"] = function(msg)
    if msg == "positions" or msg == "pos" then
        TUICD.ProfileImportExport:DumpPositionData()
    else
        print("|cff00ff00TweaksUI Debug:|r Usage:")
        print("  /tuidump positions - Show all stored position data")
    end
end
