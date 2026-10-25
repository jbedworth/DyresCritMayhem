local _, DCM = ...

-- The records window (/dcm): every ability's highest hit and crit, sorted by
-- a click on a heading (again for the other way round), with Options and
-- Reset records. A plain dialog, not a widget: it opens in the middle of the
-- screen and drags while open; nothing about it is saved but the sort. Escape
-- closes it.
local NAME = "DyresCritMayhemRecordsFrame"
local WIDTH, HEIGHT = 460, 400
local INSET = 16
local ROW_HEIGHT = 18
local HEADER_Y = -40
local LIST_TOP = -62
local FOOTER = 44
local LIST_BOTTOM = FOOTER + 18
local LIST_HEIGHT = HEIGHT + LIST_TOP - LIST_BOTTOM
-- The template's scroll bar sits right of the list: 6 apart, 16 wide, and
-- a few pixels clear of the panel's edge.
local SCROLLBAR = 26
-- Text stays this far inside its column, so numbers never touch the next one.
local CELL_PAD = 6
local STRIPE_ALPHA = 0.06
local GOLD = {1, 0.82, 0}
local WHITE = {1, 1, 1}
-- Dyre's Quest Targeting's black and gold box, a little more opaque for reading.
local PANEL = {0.05, 0.05, 0.06, 0.95}
local HEADER = {0.13, 0.13, 0.14, 0.95}
local BACKDROP = {bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = {left = 4, right = 4, top = 4, bottom = 4}}
-- Ability takes half the list, each number a quarter.
local HEADINGS = {
    {key = "name", text = "Ability", share = 0.5, justify = "LEFT"},
    {key = "hit", text = "Highest hit", share = 0.25, justify = "RIGHT"},
    {key = "crit", text = "Highest crit", share = 0.25, justify = "RIGHT"},
}
local SORT_NAMES = {name = "ability", hit = "highest hit", crit = "highest crit"}
local EMPTY = "No records yet. Go hit something!"
local GUESSED_EMPTY = "No records yet. On this client they come from combat text while you play solo: go hit "
    .. "something!"
local UNAVAILABLE = "Records need the combat log, which this client keeps from AddOns. The crit effects "
    .. "still play."

local window
local rows = {}

-- The records as a list, sorted by the saved column and direction. Numbers
-- sort high first by default; an ability without one counts as 0. Ties go
-- by name.
function DCM.SortedRecords()
    local list = {}
    for _, record in pairs(DCM.db.records) do
        list[#list + 1] = record
    end
    local key, descending = DCM.db.sortKey, DCM.db.sortDescending
    table.sort(list, function(a, b)
        local labelA, labelB = DCM.RecordLabel(a):lower(), DCM.RecordLabel(b):lower()
        if key ~= "name" then
            local valueA, valueB = a[key] or 0, b[key] or 0
            if valueA ~= valueB then
                if descending then
                    return valueA > valueB
                end
                return valueA < valueB
            end
            return labelA < labelB
        end
        if descending then
            return labelA > labelB
        end
        return labelA < labelB
    end)
    return list
end

-- A heading click: that column, or the other direction when it is the column
-- already. Names start A to Z, numbers high to low.
function DCM.SortBy(key)
    if not DCM.SORT_KEYS[key] then
        return
    end
    if DCM.db.sortKey == key then
        DCM.db.sortDescending = not DCM.db.sortDescending
    else
        DCM.db.sortKey = key
        DCM.db.sortDescending = key ~= "name"
    end
    DCM.RefreshWindow()
end

-- Column x and width in a list this wide: each column's share, the last one
-- taking what rounding leaves.
local function Columns(width)
    local columns, x = {}, 0
    for index, heading in ipairs(HEADINGS) do
        local columnWidth = index == #HEADINGS and width - x or math.floor(width * heading.share)
        columns[index] = {x = x, width = columnWidth}
        x = x + columnWidth
    end
    return columns
end

local function PlaceCell(cell, anchor, column)
    cell:ClearAllPoints()
    cell:SetPoint("LEFT", anchor, "LEFT", column.x + CELL_PAD, 0)
    cell:SetWidth(column.width - 2 * CELL_PAD)
end

local function Row(index)
    if rows[index] then
        return rows[index]
    end
    local row = CreateFrame("Frame", nil, window.list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", window.list, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(row)
        stripe:SetColorTexture(1, 1, 1, STRIPE_ALPHA)
    end
    row.cells = {}
    for column, heading in ipairs(HEADINGS) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetJustifyH(heading.justify)
        row.cells[column] = cell
    end
    rows[index] = row
    return row
end

-- The list, its rows, and the headings take the whole width when every row
-- fits; otherwise they end left of the scroll bar. Laid out from constants,
-- never from the frames' own sizes.
local function Layout(count)
    local fits = count * ROW_HEIGHT <= LIST_HEIGHT
    local width = WIDTH - 2 * INSET - (fits and 0 or SCROLLBAR)
    local scroll = window.scroll
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", INSET, LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -(WIDTH - INSET - width), LIST_BOTTOM)
    if scroll.ScrollBar then
        scroll.ScrollBar:SetShown(not fits)
    end
    if fits then
        scroll:SetVerticalScroll(0)
    end
    window.list:SetWidth(width)
    window.headerStrip:SetWidth(width)
    local columns = Columns(width)
    for column, heading in ipairs(window.headings) do
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", window, "TOPLEFT", INSET + columns[column].x, HEADER_Y)
        heading:SetSize(columns[column].width, ROW_HEIGHT)
        PlaceCell(heading.label, heading, {x = 0, width = columns[column].width})
    end
    for index = 1, count do
        local row = Row(index)
        row:SetWidth(width)
        for column, cell in ipairs(row.cells) do
            PlaceCell(cell, row, columns[column])
        end
    end
    window.listWidth, window.columns, window.fits = width, columns, fits
end

local function Amount(value)
    return value and DCM.FormatAmount(value) or "-"
end

function DCM.RefreshWindow()
    if not window or not window:IsShown() then
        return
    end
    local list = DCM.SortedRecords()
    Layout(#list)
    for index, record in ipairs(list) do
        local row = rows[index]
        row.cells[1]:SetText(DCM.RecordLabel(record))
        row.cells[2]:SetText(Amount(record.hit))
        row.cells[3]:SetText(Amount(record.crit))
        row:Show()
    end
    for index = #list + 1, #rows do
        rows[index]:Hide()
    end
    window.list:SetHeight(math.max(1, #list * ROW_HEIGHT))
    if #list == 0 then
        window.empty:SetText(not DCM.RecordsAvailable() and UNAVAILABLE
            or DCM.RecordsGuessed() and GUESSED_EMPTY or EMPTY)
        window.empty:Show()
    else
        window.empty:Hide()
    end
    for _, heading in ipairs(window.headings) do
        local color = heading.key == DCM.db.sortKey and WHITE or GOLD
        heading.label:SetTextColor(color[1], color[2], color[3])
    end
    local order
    if DCM.db.sortKey == "name" then
        order = DCM.db.sortDescending and "Z to A" or "A to Z"
    else
        order = DCM.db.sortDescending and "high to low" or "low to high"
    end
    -- Without the combat log, records are guesses made solo; the hint says so.
    window.sorted:SetText((DCM.RecordsGuessed() and "Solo guesses from combat text. " or "")
        .. "Sorted by " .. SORT_NAMES[DCM.db.sortKey] .. ", " .. order .. "."
        .. (DCM.RecordsGuessed() and "" or " Click a heading to sort."))
end

local function Button(text, width, onClick)
    local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Build()
    window = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- The family's rounded panel with a gold edge (as Dyre's Quest
    -- Targeting's black and gold box), nearly opaque for reading.
    if window.SetBackdrop then
        window:SetBackdrop(BACKDROP)
        window:SetBackdropColor(PANEL[1], PANEL[2], PANEL[3], PANEL[4])
        window:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3])
    end
    window:SetScript("OnShow", function() DCM.RefreshWindow() end)
    window:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, NAME)
    end
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", window, "TOP", 0, -14)
    title:SetText("Crit Mayhem: your records")
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
    -- A darker strip behind the headings, as wide as the list.
    window.headerStrip = window:CreateTexture(nil, "BORDER")
    window.headerStrip:SetPoint("TOPLEFT", window, "TOPLEFT", INSET, HEADER_Y)
    window.headerStrip:SetHeight(ROW_HEIGHT)
    window.headerStrip:SetColorTexture(HEADER[1], HEADER[2], HEADER[3], HEADER[4])
    window.headings = {}
    for _, heading in ipairs(HEADINGS) do
        local button = CreateFrame("Button", nil, window)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetJustifyH(heading.justify)
        label:SetText(heading.text)
        button.label, button.key = label, heading.key
        button:SetScript("OnClick", function() DCM.SortBy(heading.key) end)
        window.headings[#window.headings + 1] = button
    end
    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    -- The template then hides its bar itself whenever nothing scrolls.
    scroll.scrollBarHideable = true
    window.scroll = scroll
    window.list = CreateFrame("Frame", nil, scroll)
    window.list:SetHeight(1)
    scroll:SetScrollChild(window.list)
    window.empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    window.empty:SetPoint("TOPLEFT", window, "TOPLEFT", INSET + CELL_PAD, LIST_TOP - 8)
    window.empty:SetPoint("RIGHT", window, "RIGHT", -INSET - CELL_PAD, 0)
    window.empty:SetJustifyH("LEFT")
    window.sorted = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.sorted:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", INSET + CELL_PAD, FOOTER)
    local options = Button("Options", 110, function() DCM.OpenSettings() end)
    options:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", INSET, INSET)
    local reset = Button("Reset records", 130, function() DCM.ConfirmResetRecords() end)
    reset:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -INSET, INSET)
    DCM.window = window
end

function DCM.ToggleWindow()
    if not window then
        Build()
    end
    window:SetShown(not window:IsShown())
end
