-- ======================================================================================
-- SettingsUI.lua  (canonical: _shared/checklist/)
-- Author: Spuddeh
-- Description: Shared settings panel for the Checklist mod family — automation toggle,
--              scanner radius slider with debounce, drawCustomSettings callback.
--              Deployed byte-identical to each mod.
-- ======================================================================================

local SettingsUI = {}
local Utils = require("Modules/Utils")

--- Draws the Standard Automation Settings (Toggle, Radius)
--- @param settings table
--- @param onChanged callback
function SettingsUI.DrawAutomationSettings(settings, onChanged)
    ImGui.Separator()
    ImGui.Text("Automation Settings")

    -- 1. Automation Master Toggle
    local current_auto = settings.automation_enabled
    if current_auto == nil then current_auto = true end
    local new_auto = ImGui.Checkbox("Enable Automation", current_auto)
    if new_auto ~= current_auto then
        settings.automation_enabled = new_auto
        if onChanged then onChanged() end
    end
    ImGui.TextWrapped("Uncheck to disable all background scanning and auto-collection features.")

    if settings.automation_enabled then
        ImGui.Spacing()

        -- 2. Radius Slider (Detection Radius 25m - 100m)
        local current_radius = settings.scanner_radius or 50.0
        local new_radius = ImGui.SliderInt("Detection Radius (m)", math.floor(current_radius), 25, 100)
        if new_radius ~= math.floor(current_radius) then
            settings.scanner_radius = new_radius + 0.0
        end
        if ImGui.IsItemDeactivatedAfterEdit() then
            if onChanged then onChanged() end
        end
        ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Show map pins and check for nearby items within this distance.")
        ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Auto-collect/Snap to container happens at 25m (Fixed).")
    end
    ImGui.Spacing()
end

--- Draws the Settings UI
--- @param settings table The persistent settings table (must contain .lazy_mode)
--- @param runtimeState table A shared runtime table containing .current_mappin
--- @param callbacks table Map of callbacks: { onSettingChanged, drawCustomSettings }
function SettingsUI.Draw(settings, runtimeState, callbacks)
    if settings.dev_mode_enabled then
        ImGui.TextColored(1.0, 0.0, 0.0, 1.0, "DEV MODE ACTIVE")
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
    end

    -- Lazy Mode Toggle
    local current_mode = settings.lazy_mode
    local new_mode = ImGui.Checkbox("Lazy Mode", current_mode)
    if new_mode ~= current_mode then
        settings.lazy_mode = new_mode
        if callbacks.onSettingChanged then callbacks.onSettingChanged() end
    end
    ImGui.TextWrapped("Enables 'Teleport' buttons.")

    ImGui.Spacing()
    -- Clear Last Map Pin Button
    if ImGui.Button(IconGlyphs.MapMarkerOff .. " Clear Last Map Pin") then
        if runtimeState and runtimeState.current_mappin then
            Game.GetMappinSystem():UnregisterMappin(runtimeState.current_mappin)
            runtimeState.current_mappin = nil
            Utils.Log("Last map pin cleared.")
        else
            Utils.Log("No map pin to clear.")
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Removes the last map pin created by this mod.")
    end

    ImGui.Spacing()

    -- AUTOMATION SETTINGS (Standardized)
    SettingsUI.DrawAutomationSettings(settings, callbacks.onSettingChanged)

    ImGui.Separator()

    -- Conditional Unstuck Button (Lazy Mode Only)
    if settings.lazy_mode then
        ImGui.Spacing()
        ImGui.TextColored(1.0, 1.0, 0.0, 1.0, "WARNING:") -- Yellow color
        ImGui.TextWrapped(
            "Using teleport can sometimes get you stuck in walls or under the map. Use at your own risk and be prepared to reload a save.")

        ImGui.Spacing()
        ImGui.TextWrapped(
            "You can use this button if you get stuck in a location you can't get out of, or something goes wrong with the teleport.")
        ImGui.Spacing()

        -- Logic: Open Popup
        if ImGui.Button(IconGlyphs.Home .. " Unstuck") then
            ImGui.OpenPopup("Confirm Unstuck")
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Teleports you to a safe location (e.g., if you fall through the world).")
        end

        -- Confirmation Popup for Unstuck
        if ImGui.BeginPopupModal("Confirm Unstuck", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("Teleport to a safe location?")
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            if ImGui.Button("Yes, Teleport Me", 0, 0) then
                -- H10 Apartment (Standardized Coordinates)
                local pos = ToVector4 { x = -1378.1689, y = 1272.7375, z = 123.0649, w = 1.0 }
                local rot = ToEulerAngles { roll = 0.0, pitch = 0.0, yaw = 111.6 }
                Game.GetTeleportationFacility():Teleport(GetPlayer(), pos, rot)
                Utils.Log("Teleported to Safe Spot (H10 Apartment).")

                ImGui.CloseCurrentPopup()
            end

            ImGui.SameLine()

            if ImGui.Button("Cancel", 0, 0) then
                ImGui.CloseCurrentPopup()
            end

            ImGui.EndPopup()
        end
        ImGui.Spacing()
        ImGui.Separator()
    end

    -- Custom Settings from Mod (Injected)
    if callbacks.drawCustomSettings then
        callbacks.drawCustomSettings()
    end
end

return SettingsUI
