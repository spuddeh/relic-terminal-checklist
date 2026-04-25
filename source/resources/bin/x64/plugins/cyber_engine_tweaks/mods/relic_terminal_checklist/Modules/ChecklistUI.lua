-- ======================================================================================
-- ChecklistUI.lua  (canonical: _shared/checklist/)
-- Author: Spuddeh
-- Description: Shared ImGui rendering for the Checklist mod family — TabBar, list,
--              detail view, drawCustomActions callback. Deployed byte-identical to each mod.
-- ======================================================================================

local ChecklistUI = {}

-- State variable for internal UI state (tab selection, etc.)
ChecklistUI.state = {
    active_tab = "",
    selected_entry_id = nil,
    scroll_requested = false
}

-- Theme Colors
ChecklistUI.theme = {
    white = { 1.0, 1.0, 1.0, 1.0 },
    gold = { 1.0, 0.84, 0.0, 1.0 },
    green = { 0.0, 1.0, 0.5, 1.0 },
    light_blue = { 0.6, 0.8, 1.0, 1.0 },
    dark_blue = { 0.4, 0.6, 0.8, 1.0 },
    grey = { 0.7, 0.7, 0.7, 1.0 },
    light_grey = { 0.8, 0.8, 0.8, 1.0 },
    red = { 0.8, 0.2, 0.2, 1.0 },    -- Fallback red
    orange = { 1.0, 0.5, 0.0, 1.0 }, -- Fallback orange

    -- Detailed Button Colors (Normal, Hovered, Active)
    btn_orange = {
        { 1.0, 0.6, 0.0, 1.0 }, -- Normal
        { 1.0, 0.6, 0.0, 0.8 }, -- Hovered
        { 1.0, 0.6, 0.0, 0.6 }  -- Active
    },
    btn_red = {
        { 0.55, 0.15, 0.15, 1.0 }, -- Normal
        { 0.65, 0.2,  0.2,  1.0 }, -- Hovered
        { 0.45, 0.1,  0.1,  1.0 }  -- Active
    }
}

-- helper to get entry by ID
local function GetEntryByID(db, id)
    for _, cat in ipairs(db) do
        for _, entry in ipairs(cat.entries) do
            if entry.id == id then return entry end
        end
    end
    return nil
end

--- Draws the Checklist Window
-- @param title (string) Window Title
-- @param open (bool) Is window open?
-- @param db (table) Database table (list of {category=..., entries={...}})
-- @param progress (table) Progress table { id = boolean }
-- @param settings (table) Settings table { lazy_mode = boolean }
-- @param settings (table) Settings table { lazy_mode = boolean }
-- @param callbacks (table) Action callbacks { onToggle=fn(id, val), onAction=fn(action, entry) }
-- @param checklist_mode (string) "manual" or "automatic" (default: "manual" if unspecified)
function ChecklistUI.Draw(title, open, db, progress, settings, callbacks, checklist_mode)
    if not open then return end

    -- Default mode to manual if not provided, for backward compatibility with other mods
    -- unless implied otherwise. But user requested:
    -- "if automatic, disabled. if manual, enabled."
    -- Let's assume checklist_mode comes in as string.
    local mode = checklist_mode or "manual"

    -- Set default size
    -- Calculate dynamic min width based on tabs
    local min_tabs_width = 0
    for _, cat in ipairs(db) do
        -- Approximate tab width: Text size + Padding (Increased to 45px for safety)
        local w_x, _ = ImGui.CalcTextSize(cat.category)
        min_tabs_width = min_tabs_width + w_x + 30
    end
    -- Add Settings tab
    local set_w, _ = ImGui.CalcTextSize("Settings")
    min_tabs_width = min_tabs_width + set_w + 30
    -- Ensure a sane absolute minimum
    if min_tabs_width < 600 then min_tabs_width = 600 end

    ImGui.SetNextWindowSizeConstraints(min_tabs_width, 500, 3000, 2000)
    ImGui.SetNextWindowSize(math.max(1330, min_tabs_width), 730, ImGuiCond.FirstUseEver)

    if ImGui.Begin(title, true) then
        -- Main Content Area
        local footer_height = ImGui.GetTextLineHeightWithSpacing() + 10
        local window_width = ImGui.GetWindowContentRegionWidth()
        local list_col_width = window_width * 0.4

        ImGui.BeginChild("MainContent", 0, -footer_height, false, 0)

        if ImGui.BeginTabBar("MainTabBar") then
            -- Iterate Categories
            for _, cat in ipairs(db) do
                if ImGui.BeginTabItem(cat.category) then
                    -- Handle Tab Switching Defaults
                    if ChecklistUI.state.active_tab ~= cat.category then
                        ChecklistUI.state.active_tab = cat.category
                        if cat.entries[1] then
                            ChecklistUI.state.selected_entry_id = cat.entries[1].id
                        else
                            ChecklistUI.state.selected_entry_id = nil
                        end
                    end

                    -- ### LEFT COLUMN (List) ###
                    ImGui.BeginChild("ListCol", list_col_width, 0, true, ImGuiWindowFlags.NoMove)

                    for _, entry in ipairs(cat.entries) do
                        local is_checked = progress[entry.id] == true

                        -- Checkbox
                        -- Enable only if manual mode AND callback exists
                        local can_toggle = (mode == "manual") and (callbacks.onToggle ~= nil)

                        if not can_toggle then
                            ImGui.BeginDisabled()
                        end

                        local new_val = ImGui.Checkbox("##" .. entry.id, is_checked)

                        if not can_toggle then
                            ImGui.EndDisabled()
                        end

                        if new_val ~= is_checked and can_toggle then
                            callbacks.onToggle(entry.id, new_val)
                        end

                        ImGui.SameLine()

                        -- Color
                        if is_checked then
                            ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.green))
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.white))
                        end

                        -- Selectable
                        if ImGui.Selectable(entry.name, ChecklistUI.state.selected_entry_id == entry.id) then
                            ChecklistUI.state.selected_entry_id = entry.id
                        end

                        ImGui.PopStyleColor()
                        ImGui.Spacing()
                    end

                    ImGui.EndChild()

                    ImGui.SameLine()

                    -- ### RIGHT COLUMN (Details) ###
                    -- Disable scrolling on the parent column so Header/Footer stay fixed
                    ImGui.BeginChild("DetailCol", 0, 0, true,
                        ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoScrollbar + ImGuiWindowFlags.NoScrollWithMouse)

                    local selected_entry = GetEntryByID(db, ChecklistUI.state.selected_entry_id)

                    if selected_entry then
                        -- 1. FIXED HEADER (Item Name)
                        ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.gold))
                        ImGui.TextWrapped(selected_entry.name)
                        ImGui.PopStyleColor()
                        ImGui.Separator()

                        -- Calculate heights
                        local footer_height = ImGui.GetFrameHeight() + 20 -- Standard Button row + padding

                        -- Increase footer space if Gig Coords present (Extra row of buttons + Text)
                        if selected_entry.gig_coords then
                            footer_height = footer_height + ImGui.GetFrameHeight() + 20 -- Standard Button row + padding
                        end
                        local _, avail_h = ImGui.GetContentRegionAvail()
                        local body_h = avail_h - footer_height

                        -- 2. SCROLLABLE BODY (Data)
                        ImGui.BeginChild("DetailBody", 0, body_h, false, ImGuiWindowFlags.AlwaysUseWindowPadding)
                        ImGui.Spacing()

                        -- BaseID
                        if settings and settings.show_baseid and selected_entry.baseID then
                            ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.dark_blue))
                            ImGui.Text("BaseID:")
                            ImGui.PopStyleColor()

                            ImGui.SetCursorPosX(ImGui.GetCursorPosX() + 15)
                            ImGui.Text(selected_entry.baseID)
                            ImGui.Spacing()
                        end

                        -- District Info
                        if selected_entry.district or selected_entry.sub_district then
                            local has_district = (selected_entry.district and selected_entry.district ~= "")
                            local has_sub = (selected_entry.sub_district and selected_entry.sub_district ~= "")

                            if has_district or has_sub then
                                ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.dark_blue))
                                ImGui.Text("District:")
                                ImGui.PopStyleColor()

                                if has_sub then
                                    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + 15)
                                    ImGui.Text(selected_entry.sub_district .. ", " .. (selected_entry.district or ""))
                                elseif has_district then
                                    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + 15)
                                    ImGui.Text(selected_entry.district)
                                end
                                ImGui.Spacing()
                            end
                        end

                        -- Fast Travel
                        if selected_entry.fast_travel and selected_entry.fast_travel ~= "" and selected_entry.fast_travel ~= "TBD" then
                            ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.dark_blue))
                            ImGui.Text("Closest Fast Travel:")
                            ImGui.PopStyleColor()

                            ImGui.SetCursorPosX(ImGui.GetCursorPosX() + 15)
                            ImGui.Text(selected_entry.fast_travel)
                            ImGui.Spacing()
                        end

                        -- Requirements
                        if selected_entry.requirement and selected_entry.requirement ~= "" then
                            ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.red))
                            ImGui.Text("Requirements:")
                            ImGui.PopStyleColor()

                            ImGui.SetCursorPosX(ImGui.GetCursorPosX() + 15)
                            ImGui.Text(selected_entry.requirement)
                            ImGui.Spacing()
                        end

                        -- Description / Directions
                        local desc = selected_entry.description or selected_entry.directions
                        if desc and desc ~= "" then
                            ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.dark_blue))
                            ImGui.Text("Directions:")
                            ImGui.PopStyleColor()

                            ImGui.SetCursorPosX(ImGui.GetCursorPosX() + 15)
                            ImGui.TextWrapped(desc)
                            ImGui.Spacing()
                        end

                        ImGui.EndChild() -- End DetailBody

                        -- 3. FIXED FOOTER (Buttons)
                        -- Always show footer for Set Pin, check logic inside for others
                        ImGui.Separator()
                        ImGui.Spacing()

                        local has_coords = (selected_entry.coords and selected_entry.coords.x ~= 0)

                        -- 1) Set Pin (Always Visible - Default Blue)
                        if has_coords then
                            if ImGui.Button(IconGlyphs.MapMarker .. " Set Pin") then
                                if callbacks.onAction then callbacks.onAction("mappin", selected_entry) end
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip(
                                    "Place a custom map marker at the item location.")
                            end
                        else
                            ImGui.BeginDisabled()
                            ImGui.Button(IconGlyphs.MapMarker .. " Set Pin")
                            ImGui.EndDisabled()
                            if ImGui.IsItemHovered() then ImGui.SetTooltip("Coordinates TBD") end
                            if ImGui.IsItemHovered() then ImGui.SetTooltip("Coordinates TBD") end
                        end

                        if settings and settings.lazy_mode then
                            ImGui.SameLine()

                            -- 2) Teleport (Orange)
                            if has_coords then
                                local c = ChecklistUI.theme.btn_orange
                                ImGui.PushStyleColor(ImGuiCol.Button, unpack(c[1]))
                                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, unpack(c[2]))
                                ImGui.PushStyleColor(ImGuiCol.ButtonActive, unpack(c[3]))
                                if ImGui.Button(IconGlyphs.Directions .. " Teleport") then
                                    if callbacks.onAction then callbacks.onAction("teleport", selected_entry) end
                                end
                                ImGui.PopStyleColor(3)
                                if ImGui.IsItemHovered() then ImGui.SetTooltip("Teleport nearby the item location.") end
                            else
                                ImGui.BeginDisabled()
                                ImGui.Button(IconGlyphs.Directions .. " Teleport")
                                ImGui.EndDisabled()
                                if ImGui.IsItemHovered() then ImGui.SetTooltip("Coordinates TBD") end
                            end

                            -- 3) Give Item (Red)
                            if callbacks.drawCustomActions then
                                ImGui.SameLine()
                                local c = ChecklistUI.theme.btn_red
                                ImGui.PushStyleColor(ImGuiCol.Button, unpack(c[1]))
                                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, unpack(c[2]))
                                ImGui.PushStyleColor(ImGuiCol.ButtonActive, unpack(c[3]))
                                callbacks.drawCustomActions(selected_entry)
                                ImGui.PopStyleColor(3)
                            end
                        end -- End settings.lazy_mode check for extra buttons

                        -- ### GIG COORDS SUPPORT ###
                        if selected_entry.gig_coords then
                            ImGui.Spacing()
                            ImGui.Spacing()

                            if ImGui.Button(IconGlyphs.MapMarker .. " Pin Gig Start") then
                                if callbacks.onAction then callbacks.onAction("gig_mappin", selected_entry) end
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Place map marker at the Gig start location.")
                            end

                            if settings and settings.lazy_mode then
                                ImGui.SameLine()
                                local c = ChecklistUI.theme.btn_orange
                                ImGui.PushStyleColor(ImGuiCol.Button, unpack(c[1]))
                                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, unpack(c[2]))
                                ImGui.PushStyleColor(ImGuiCol.ButtonActive, unpack(c[3]))
                                if ImGui.Button(IconGlyphs.Directions .. " TP to Gig") then
                                    if callbacks.onAction then callbacks.onAction("gig_teleport", selected_entry) end
                                end
                                ImGui.PopStyleColor(3)
                                if ImGui.IsItemHovered() then ImGui.SetTooltip("Teleport to the Gig start location.") end
                            end
                        end
                    else
                        ImGui.Text("Select an item to see details.")
                    end

                    ImGui.EndChild() -- End DetailCol

                    ImGui.EndTabItem()
                end
            end

            -- ### SETTINGS TAB ###
            if ImGui.BeginTabItem("Settings") then
                -- Override active tab name to avoid showing stats for last selected category
                ChecklistUI.state.active_tab = "Settings"

                ImGui.Spacing()

                if callbacks.drawSettings then
                    callbacks.drawSettings()
                end

                ImGui.EndTabItem()
            end

            ImGui.EndTabBar()
        end

        ImGui.EndChild()

        -- ### FOOTER ###
        -- Stats Variables
        local global_total = 0
        local global_collected = 0
        local total_sets = 0
        local completed_sets = 0

        -- Current Tab Stats
        local current_set_name = ChecklistUI.state.active_tab
        local current_set_total = 0
        local current_set_collected = 0

        -- Calculate totals
        for _, cat in ipairs(db) do
            total_sets = total_sets + 1
            local set_total = 0
            local set_collected = 0

            for _, entry in ipairs(cat.entries) do
                set_total = set_total + 1
                if progress[entry.id] then
                    set_collected = set_collected + 1
                end
            end

            -- Update Global
            global_total = global_total + set_total
            global_collected = global_collected + set_collected

            -- Update Completed Sets
            if set_total > 0 and set_collected == set_total then
                completed_sets = completed_sets + 1
            end

            -- Update Current Set Stats
            if cat.category == current_set_name then
                current_set_total = set_total
                current_set_collected = set_collected
            end
        end

        local footer_y = ImGui.GetWindowHeight() - ImGui.GetFrameHeightWithSpacing() -- Check padding

        ImGui.SetCursorPosY(footer_y)

        -- Left: Current Set Stats
        -- Format: "Current Set: [Name] (Collected/Total)"
        -- Hide if no set selected or if in Settings
        if current_set_name ~= "" and current_set_name ~= "Settings" then
            ImGui.Text(string.format("Current Set: %s (%d/%d)", current_set_name, current_set_collected,
                current_set_total))
        end

        -- Right: Global Stats & Completion
        -- Format: "Sets: C/T | Items: C/T" (plus Nova if done)
        local right_text = string.format("Sets: %d/%d | Items: %d/%d", completed_sets, total_sets, global_collected,
            global_total)

        if global_total > 0 and global_collected == global_total then
            right_text = IconGlyphs.Trophy .. " Nova! " .. right_text
            ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.green))
        end

        if current_set_name ~= "" and current_set_name ~= "Settings" then
            ImGui.SameLine()
        end
        ImGui.SetCursorPosX(ImGui.GetWindowWidth() - ImGui.CalcTextSize(right_text) - 20)
        ImGui.Text(right_text)

        if global_total > 0 and global_collected == global_total then
            ImGui.PopStyleColor()
        end
    end
    ImGui.End()
end

--- Draws a Splash Screen (for Main Menu)
-- @param title (string) Window Title / Mod Name
function ChecklistUI.DrawSplashScreen(title)
    -- Set a reasonable fixed size for the splash screen
    ImGui.SetNextWindowSize(400, 200, ImGuiCond.FirstUseEver)

    local flags = ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoCollapse + ImGuiWindowFlags.NoScrollbar

    if ImGui.Begin(title, true, flags) then
        -- Center content vertically and horizontally roughly
        local windowWidth = ImGui.GetWindowWidth()
        local windowHeight = ImGui.GetWindowHeight()

        local text = "Please load a save game to view the checklist."
        local subtext = "Checklist will load on gameplay start."

        -- Calculate centered position
        local textWidth = ImGui.CalcTextSize(text)
        local subtextWidth = ImGui.CalcTextSize(subtext)

        local cursorX = (windowWidth - textWidth) * 0.5
        local cursorY = (windowHeight * 0.4)

        ImGui.SetCursorPos(cursorX, cursorY)
        ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.gold))
        ImGui.Text(text)
        ImGui.PopStyleColor()

        ImGui.SetCursorPos((windowWidth - subtextWidth) * 0.5, cursorY + ImGui.GetTextLineHeightWithSpacing() * 2)
        ImGui.PushStyleColor(ImGuiCol.Text, unpack(ChecklistUI.theme.light_grey))
        ImGui.Text(subtext)
        ImGui.PopStyleColor()
    end
    ImGui.End()
end

return ChecklistUI
