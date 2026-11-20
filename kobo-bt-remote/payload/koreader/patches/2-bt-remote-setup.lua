--[[
2-bt-remote-setup.lua  (KOReader user patch, priority 2 = "late")

Prepares kobo.koplugin (OGKevin) for a Bluetooth remote such as an 8BitDo
Micro, so it connects by itself and turns pages without manual setup:

  1. Once: switches on the plugin's Bluetooth automation
       - Bluetooth on when KOReader starts
       - Bluetooth back on after waking from sleep
       - auto-connect to paired remotes + auto-detect remotes that reconnect
     and switches off the plugin's virtual library and Kobo progress sync for
     a fresh install (BookOrbit already handles library and sync).
     Settings you change afterwards in the menu are left alone.
  2. Once: disables other Bluetooth/page-turner plugins (for example
     bluetooth.koplugin) on devices that kobo.koplugin supports, so two
     plugins do not fight over the Bluetooth stack. You can re-enable them
     under Tools > More tools > Plugin management.
  3. Every run: a remote that has no key bindings yet gets a default
     page-turn layout the first time one of its buttons is pressed.
     Bindings you register yourself are never overwritten.

Remove this file (koreader/patches/2-bt-remote-setup.lua) to undo step 3;
steps 1 and 2 are normal settings you can change in the menus.
]]

local logger = require("logger")

local TAG = "bt-remote-setup:"
local SETUP_VERSION = 1

-- Linux input key codes. 8BitDo Micro / Zero 2 in keyboard mode send arrow
-- keys for the D-pad; generic page turners send PageUp/PageDown, Space or
-- media keys.
local NEXT_PAGE_KEYS = {
    106, -- KEY_RIGHT
    108, -- KEY_DOWN
    109, -- KEY_PAGEDOWN
    57, -- KEY_SPACE
    163, -- KEY_NEXTSONG
    115, -- KEY_VOLUMEUP
}
local PREV_PAGE_KEYS = {
    105, -- KEY_LEFT
    103, -- KEY_UP
    104, -- KEY_PAGEUP
    165, -- KEY_PREVIOUSSONG
    114, -- KEY_VOLUMEDOWN
}

-- Plugin folder names (without .koplugin) that look like another Bluetooth
-- or page-turner plugin.
local CONFLICT_PATTERNS = { "bluetooth", "^bt", "pageturn", "page_turn", "btremote" }

local function deviceSupported(Device)
    if not Device:isKobo() then
        return false
    end
    if Device.model == "Kobo_io" then -- Libra 2
        return true
    end
    -- MTK models: Libra Colour, Clara BW, Clara Colour, Elipsa 2E
    local ok, is_mtk = pcall(function()
        return type(Device.isMTK) == "function" and Device:isMTK()
    end)
    return ok and is_mtk == true
end

local function pluginInstalled(name)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        return false
    end
    local DataStorage = require("datastorage")
    for _, dir in ipairs({ DataStorage:getDataDir() .. "/plugins", "plugins" }) do
        if lfs.attributes(dir .. "/" .. name .. ".koplugin", "mode") == "directory" then
            return true
        end
    end
    return false
end

local function listConflictingPlugins()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        return {}
    end
    local DataStorage = require("datastorage")
    local found, seen = {}, {}
    for _, dir in ipairs({ DataStorage:getDataDir() .. "/plugins", "plugins" }) do
        if lfs.attributes(dir, "mode") == "directory" then
            for entry in lfs.dir(dir) do
                local name = entry:match("^(.+)%.koplugin$")
                if name and name ~= "kobo" and not seen[name] then
                    local lower = name:lower()
                    for _, pattern in ipairs(CONFLICT_PATTERNS) do
                        if lower:find(pattern) then
                            seen[name] = true
                            table.insert(found, name)
                            break
                        end
                    end
                end
            end
        end
    end
    return found
end

--- Step 1 + 2: one-time settings.
local function applyOneTimeSettings(Device)
    local settings = G_reader_settings:readSetting("kobo_plugin")
    local fresh_install = settings == nil
    settings = settings or {}

    if (settings.bt_remote_setup_version or 0) >= SETUP_VERSION then
        return
    end

    settings.enable_bluetooth_on_startup = true
    settings.enable_bluetooth_auto_resume = true
    settings.enable_auto_connect_polling = true
    settings.disable_auto_connect_after_connect = true -- scanning resumes by itself on disconnect
    settings.enable_auto_detection_polling = true
    settings.disable_auto_detection_after_connect = true
    settings.show_device_ready_notifications = true
    settings.dismiss_widgets_on_button = true
    if fresh_install then
        -- BookOrbit already does library + progress sync; keep this plugin to Bluetooth only.
        settings.enable_virtual_library = false
        settings.sync_reading_state = false
    end
    settings.bt_remote_setup_version = SETUP_VERSION
    G_reader_settings:saveSetting("kobo_plugin", settings)
    logger.info(TAG, "applied Bluetooth remote settings to kobo_plugin")

    if deviceSupported(Device) then
        local disabled = G_reader_settings:readSetting("plugins_disabled") or {}
        local names = {}
        for _, name in ipairs(listConflictingPlugins()) do
            if not disabled[name] then
                disabled[name] = true
                table.insert(names, name)
            end
        end
        if #names > 0 then
            G_reader_settings:saveSetting("plugins_disabled", disabled)
            logger.info(TAG, "disabled conflicting plugins:", table.concat(names, ", "))
        end
    else
        logger.warn(TAG, "this Kobo model is not supported by kobo.koplugin's Bluetooth;",
            "other Bluetooth plugins were left enabled")
    end

    G_reader_settings:flush()
end

--- Step 3: default bindings for remotes without any.
local function findAction(kb, wanted_id, wanted_args)
    local _ = require("gettext")
    local direct = kb:getActionById(_("Reader") .. ":" .. wanted_id)
    if direct then
        return _("Reader") .. ":" .. wanted_id
    end
    for prefixed_id, action in pairs(kb.action_lookup_map or {}) do
        if prefixed_id:match(":" .. wanted_id .. "$") and action.event == "GotoViewRel" and action.args == wanted_args then
            return prefixed_id
        end
    end
    return nil
end

local function seedBindings(kb, device_path)
    local mac = kb.device_path_to_address and kb.device_path_to_address[device_path]
    if not mac or type(kb.device_bindings) ~= "table" or kb.device_bindings[mac] ~= nil then
        return
    end
    local next_id = findAction(kb, "next_page", 1)
    local prev_id = findAction(kb, "prev_page", -1)
    if not next_id or not prev_id then
        logger.warn(TAG, "page-turn actions not found, skipping default bindings")
        return
    end
    local bindings = {}
    for _, code in ipairs(NEXT_PAGE_KEYS) do
        bindings["KEY_" .. code] = next_id
    end
    for _, code in ipairs(PREV_PAGE_KEYS) do
        bindings["KEY_" .. code] = prev_id
    end
    kb.device_bindings[mac] = bindings
    kb:saveBindings()
    logger.info(TAG, "default page-turn bindings created for", mac)

    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    local ok_msg, Notification = pcall(require, "ui/widget/notification")
    if ok_ui and ok_msg then
        UIManager:show(Notification:new({ text = "Afstandsbediening klaar: pijltjes = bladeren" }))
    end
end

local function hookKeyBindings()
    local KB = package.loaded["src/bluetooth_keybindings"]
    if type(KB) ~= "table" then
        return false
    end
    if KB._bt_remote_setup_hooked then
        return true
    end
    local original = KB.onBluetoothKeyEvent
    if type(original) ~= "function" then
        logger.warn(TAG, "kobo.koplugin has no onBluetoothKeyEvent; default bindings disabled")
        return true
    end
    KB.onBluetoothKeyEvent = function(self, key_code, key_value, time, device_path)
        if key_value == 1 and not self.is_capturing then
            local ok, err = pcall(seedBindings, self, device_path)
            if not ok then
                logger.warn(TAG, "seeding bindings failed:", err)
            end
        end
        return original(self, key_code, key_value, time, device_path)
    end
    KB._bt_remote_setup_hooked = true
    logger.info(TAG, "default-binding hook installed")
    return true
end

local ok, err = pcall(function()
    local Device = require("device")
    if not Device:isKobo() then
        return
    end
    if not pluginInstalled("kobo") then
        logger.warn(TAG, "kobo.koplugin not installed, nothing to do")
        return
    end

    applyOneTimeSettings(Device)

    -- Plugins are loaded after late patches; hook once they are in.
    local UIManager = require("ui/uimanager")
    local tries = 0
    local function tryHook()
        tries = tries + 1
        if not hookKeyBindings() and tries < 10 then
            UIManager:scheduleIn(2, tryHook)
        end
    end
    UIManager:nextTick(tryHook)
end)

if not ok then
    logger.warn(TAG, "patch failed:", err)
end
