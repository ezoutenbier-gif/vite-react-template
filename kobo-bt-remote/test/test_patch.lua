-- Runs payload/koreader/patches/2-bt-remote-setup.lua against small fakes of
-- the KOReader modules it uses. Usage: luajit test/test_patch.lua (from kobo-bt-remote/)

local PATCH = arg[1] or "payload/koreader/patches/2-bt-remote-setup.lua"
local failures = 0
local function check(cond, msg)
    if cond then
        print("ok   " .. msg)
    else
        failures = failures + 1
        print("FAIL " .. msg)
    end
end

local function fakeSettings(initial)
    local data = initial or {}
    return {
        data = data,
        flushed = 0,
        readSetting = function(self, k)
            return self.data[k]
        end,
        saveSetting = function(self, k, v)
            self.data[k] = v
        end,
        flush = function(self)
            self.flushed = self.flushed + 1
        end,
    }
end

local function setup(opts)
    for _, m in ipairs({ "logger", "device", "datastorage", "libs/libkoreader-lfs", "ui/uimanager",
        "ui/widget/notification", "gettext", "src/bluetooth_keybindings" }) do
        package.loaded[m] = nil
    end
    local log = {}
    package.loaded["logger"] = {
        info = function(...) table.insert(log, table.concat({ ... }, " ")) end,
        warn = function(...) table.insert(log, "WARN " .. table.concat({ ... }, " ")) end,
    }
    package.loaded["device"] = {
        model = opts.model,
        isKobo = function() return true end,
        isMTK = function() return opts.mtk == true end,
    }
    package.loaded["datastorage"] = { getDataDir = function() return "/kr" end }
    local dirs = opts.plugins
    package.loaded["libs/libkoreader-lfs"] = {
        attributes = function(path, what)
            if path == "/kr/plugins" then return "directory" end
            for _, d in ipairs(dirs) do
                if path == "/kr/plugins/" .. d then return "directory" end
            end
            return nil
        end,
        dir = function(path)
            local i = 0
            return function()
                i = i + 1
                return dirs[i]
            end
        end,
    }
    local ticks = {}
    package.loaded["ui/uimanager"] = {
        nextTick = function(_, f) table.insert(ticks, f) end,
        scheduleIn = function(_, _, f) table.insert(ticks, f) end,
        show = function() end,
    }
    package.loaded["ui/widget/notification"] = { new = function(_, o) return o end }
    package.loaded["gettext"] = function(s) return opts.translate and opts.translate[s] or s end
    _G.G_reader_settings = fakeSettings(opts.settings)
    return log, ticks
end

local function fakeKeyBindings(category)
    local calls = {}
    local KB = {
        is_capturing = false,
        device_bindings = {},
        device_path_to_address = { ["/dev/input/event4"] = "AA:BB" },
        saved = 0,
    }
    function KB:getActionById(id)
        self.action_lookup_map = self.action_lookup_map or {
            [category .. ":next_page"] = { event = "GotoViewRel", args = 1 },
            [category .. ":prev_page"] = { event = "GotoViewRel", args = -1 },
        }
        return self.action_lookup_map[id]
    end
    function KB:saveBindings() self.saved = self.saved + 1 end
    function KB:onBluetoothKeyEvent(code, value, time, path)
        table.insert(calls, { code = code, value = value, bindings = self.device_bindings[self.device_path_to_address[path]] })
    end
    return KB, calls
end

local function runTicks(ticks)
    while #ticks > 0 do
        table.remove(ticks, 1)()
    end
end

-- 1. Supported MTK device, fresh install, old plugin present
do
    print("-- MTK, fresh install")
    local log, ticks = setup({ model = "Kobo_spaBW", mtk = true,
        plugins = { "kobo.koplugin", "bluetooth.koplugin", "statistics.koplugin" } })
    dofile(PATCH)
    local s = G_reader_settings.data.kobo_plugin
    check(s and s.enable_bluetooth_on_startup == true, "enable on startup set")
    check(s.enable_auto_connect_polling == true and s.enable_auto_detection_polling == true, "auto-connect + auto-detect set")
    check(s.enable_bluetooth_auto_resume == true, "auto-resume set")
    check(s.enable_virtual_library == false and s.sync_reading_state == false, "virtual library + sync off on fresh install")
    local dis = G_reader_settings.data.plugins_disabled
    check(dis and dis.bluetooth == true, "bluetooth.koplugin disabled")
    check(dis.statistics == nil and dis.kobo == nil, "other plugins untouched")

    local KB, calls = fakeKeyBindings("Reader")
    package.loaded["src/bluetooth_keybindings"] = KB
    runTicks(ticks)
    KB:onBluetoothKeyEvent(106, 1, nil, "/dev/input/event4")
    local b = KB.device_bindings["AA:BB"]
    check(b and b.KEY_106 == "Reader:next_page" and b.KEY_105 == "Reader:prev_page", "default bindings seeded")
    check(calls[1] and calls[1].bindings == b, "original handler called with seeded bindings")
    check(KB.saved == 1, "bindings saved once")

    b.KEY_106 = "Reader:prev_page"
    KB:onBluetoothKeyEvent(106, 1, nil, "/dev/input/event4")
    check(KB.device_bindings["AA:BB"].KEY_106 == "Reader:prev_page" and KB.saved == 1, "user bindings not overwritten")
end

-- 2. Already configured: user changed a setting later, must not be reset
do
    print("-- second run")
    setup({ model = "Kobo_io", plugins = { "kobo.koplugin", "bluetooth.koplugin" },
        settings = { kobo_plugin = { bt_remote_setup_version = 1, enable_auto_connect_polling = false },
            plugins_disabled = {} } })
    dofile(PATCH)
    check(G_reader_settings.data.kobo_plugin.enable_auto_connect_polling == false, "user choice kept on later runs")
    check(next(G_reader_settings.data.plugins_disabled) == nil, "re-enabled plugin stays enabled")
end

-- 3. Existing kobo_plugin settings: virtual library choice kept
do
    print("-- upgrade from existing kobo.koplugin")
    setup({ model = "Kobo_io", plugins = { "kobo.koplugin" },
        settings = { kobo_plugin = { enable_virtual_library = true } } })
    dofile(PATCH)
    local s = G_reader_settings.data.kobo_plugin
    check(s.enable_virtual_library == true, "existing virtual library choice kept")
    check(s.enable_bluetooth_on_startup == true, "BT automation added")
end

-- 4. Unsupported model (Sage): old plugin stays enabled
do
    print("-- unsupported model")
    local log = setup({ model = "Kobo_cadmus", mtk = false, plugins = { "kobo.koplugin", "bluetooth.koplugin" } })
    dofile(PATCH)
    check(G_reader_settings.data.plugins_disabled == nil, "nothing disabled on unsupported model")
end

-- 5. Dutch UI: category title translated
do
    print("-- translated category")
    local _, ticks = setup({ model = "Kobo_io", plugins = { "kobo.koplugin" }, translate = { Reader = "Lezer" } })
    dofile(PATCH)
    local KB = fakeKeyBindings("Lezer")
    package.loaded["src/bluetooth_keybindings"] = KB
    runTicks(ticks)
    KB:onBluetoothKeyEvent(108, 1, nil, "/dev/input/event4")
    check(KB.device_bindings["AA:BB"] and KB.device_bindings["AA:BB"].KEY_108 == "Lezer:next_page", "works with translated category")
end

-- 6. kobo.koplugin missing: no changes
do
    print("-- plugin missing")
    setup({ model = "Kobo_io", plugins = { "bluetooth.koplugin" } })
    dofile(PATCH)
    check(G_reader_settings.data.kobo_plugin == nil, "no settings written without kobo.koplugin")
end

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
