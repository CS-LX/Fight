-- ============================================================================
-- ui/components/FolderTabs.lua - Folder Tab / Pill Toggle 组件
-- ============================================================================
-- 纯 UI 组件实现的标签页组件，提供两种风格：
--   1. FolderTabs  — 文件夹标签页（选中Tab与面板同色融合）
--   2. PillToggle  — 胶囊切换按钮（圆角滑块指示器）
-- ============================================================================

local UI = require("urhox-libs/UI")

local M = {}

-- ============================================================================
-- 设计常量
-- ============================================================================

local FOLDER_COLORS = {
    panelBg     = { 30, 30, 42, 255 },     -- 面板/选中Tab背景（融合色）
    tabNormal   = { 20, 20, 28, 200 },     -- 未选中Tab背景
    tabBorder   = { 55, 60, 80, 120 },     -- Tab边框色
    accent      = { 80, 180, 255, 255 },   -- 选中指示条
    textActive  = { 240, 240, 250, 255 },  -- 选中文字
    textNormal  = { 130, 135, 150, 200 },  -- 未选中文字
}

local PILL_COLORS = {
    trackBg     = { 28, 30, 42, 220 },     -- 底层背景轨道
    selFill     = { 80, 160, 255, 50 },    -- 选中胶囊填充
    selBorder   = { 80, 160, 255, 160 },   -- 选中胶囊描边
    textActive  = { 120, 200, 255, 245 },  -- 选中文字
    textNormal  = { 130, 135, 150, 170 },  -- 未选中文字
}

-- ============================================================================
-- FolderTabs — 文件夹标签页
-- ============================================================================

--- 创建文件夹标签页组件
---@param opts {tabs: {id:string, label:string}[], activeId: string, onSwitch: fun(id:string), height?: number}
---@return Widget tabBar, table api
function M.CreateFolderTabs(opts)
    local tabs = opts.tabs
    local activeId = opts.activeId or tabs[1].id
    local onSwitch = opts.onSwitch
    local tabH = opts.height or 34

    local tabRefs = {}
    local indicatorRefs = {}
    local labelRefs = {}

    local function refreshHighlight()
        for i, tab in ipairs(tabs) do
            local isActive = (tab.id == activeId)
            tabRefs[i]:SetBackgroundColor(isActive and FOLDER_COLORS.panelBg or FOLDER_COLORS.tabNormal)
            tabRefs[i]:SetBorderColor(isActive and { 55, 60, 80, 0 } or FOLDER_COLORS.tabBorder)
            indicatorRefs[i]:SetBackgroundColor(isActive and FOLDER_COLORS.accent or { 0, 0, 0, 0 })
            labelRefs[i]:SetFontColor(isActive and FOLDER_COLORS.textActive or FOLDER_COLORS.textNormal)
        end
    end

    local children = {}
    for i, tab in ipairs(tabs) do
        local indicator = UI.Panel {
            width = "80%", height = 3,
            borderRadius = 1.5,
            backgroundColor = (tab.id == activeId) and FOLDER_COLORS.accent or { 0, 0, 0, 0 },
            position = "absolute",
            bottom = 0,
            alignSelf = "center",
            left = "10%",
        }
        local label = UI.Label {
            text = tab.label,
            fontSize = 13,
            fontColor = (tab.id == activeId) and FOLDER_COLORS.textActive or FOLDER_COLORS.textNormal,
        }
        local tabBtn = UI.Panel {
            height = tabH,
            paddingLeft = 14, paddingRight = 14,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = (tab.id == activeId) and FOLDER_COLORS.panelBg or FOLDER_COLORS.tabNormal,
            borderRadius = 8,
            borderBottomLeftRadius = 0,
            borderBottomRightRadius = 0,
            borderWidth = 1,
            borderColor = (tab.id == activeId) and { 55, 60, 80, 0 } or FOLDER_COLORS.tabBorder,
            borderBottomWidth = 0,
            cursor = "pointer",
            onClick = function()
                if activeId == tab.id then return end
                activeId = tab.id
                refreshHighlight()
                if onSwitch then onSwitch(tab.id) end
            end,
            children = { label, indicator },
        }
        tabRefs[i] = tabBtn
        indicatorRefs[i] = indicator
        labelRefs[i] = label
        children[#children + 1] = tabBtn
    end

    local tabBar = UI.Panel {
        width = "100%", height = tabH,
        flexDirection = "row",
        alignItems = "flex-end",
        backgroundColor = { 22, 22, 30, 255 },
        paddingLeft = 8,
        gap = 2,
        children = children,
    }

    local api = {
        SetActive = function(id)
            activeId = id
            refreshHighlight()
        end,
        GetActive = function() return activeId end,
    }

    return tabBar, api
end

-- ============================================================================
-- PillToggle — 胶囊切换按钮
-- ============================================================================

--- 创建胶囊切换按钮
---@param opts {tabs: {id:string, label:string, color?:table}[], activeId: string, onSwitch: fun(id:string), height?: number, fontSize?: number, trackColor?: table}
---@return Widget pill, table api
function M.CreatePillToggle(opts)
    local tabs = opts.tabs
    local activeId = opts.activeId or tabs[1].id
    local onSwitch = opts.onSwitch
    local pillH = opts.height or 30
    local fontSize = opts.fontSize or 12
    local trackColor = opts.trackColor or PILL_COLORS.trackBg

    local labelRefs = {}
    local segRefs = {}
    local selectorRef = nil

    -- 获取选中项颜色
    local function getSelColor()
        for _, tab in ipairs(tabs) do
            if tab.id == activeId and tab.color then
                return tab.color
            end
        end
        return { 80, 160, 255 }
    end

    local function refreshHighlight()
        local selColor = getSelColor()
        local selFill = { selColor[1], selColor[2], selColor[3], 50 }
        local selBorder = { selColor[1], selColor[2], selColor[3], 160 }
        local selText = { selColor[1], selColor[2], selColor[3], 245 }

        for i, tab in ipairs(tabs) do
            local isActive = (tab.id == activeId)
            labelRefs[i]:SetFontColor(isActive and selText or PILL_COLORS.textNormal)
            segRefs[i]:SetBackgroundColor(isActive and selFill or { 0, 0, 0, 0 })
            segRefs[i]:SetBorderColor(isActive and selBorder or { 0, 0, 0, 0 })
        end
    end

    local children = {}
    for i, tab in ipairs(tabs) do
        local isActive = (tab.id == activeId)
        local selColor = getSelColor()

        local label = UI.Label {
            text = tab.label,
            fontSize = fontSize,
            fontColor = isActive and { selColor[1], selColor[2], selColor[3], 245 } or PILL_COLORS.textNormal,
        }

        local seg = UI.Panel {
            flexGrow = 1,
            height = "100%",
            justifyContent = "center",
            alignItems = "center",
            borderRadius = pillH / 2,
            backgroundColor = isActive and { selColor[1], selColor[2], selColor[3], 50 } or { 0, 0, 0, 0 },
            borderWidth = 1,
            borderColor = isActive and { selColor[1], selColor[2], selColor[3], 160 } or { 0, 0, 0, 0 },
            cursor = "pointer",
            onClick = function()
                if activeId == tab.id then return end
                activeId = tab.id
                refreshHighlight()
                if onSwitch then onSwitch(tab.id) end
            end,
            children = { label },
        }

        labelRefs[i] = label
        segRefs[i] = seg
        children[#children + 1] = seg
    end

    local pill = UI.Panel {
        width = "100%",
        height = pillH,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = trackColor,
        borderRadius = pillH / 2,
        padding = 3,
        gap = 2,
        children = children,
    }

    local api = {
        SetActive = function(id)
            activeId = id
            refreshHighlight()
        end,
        GetActive = function() return activeId end,
    }

    return pill, api
end

return M
