-- blaze_bossmenu | GNU GPL v3 (see LICENSE) | based on qbx_management by the Qbox Project (see NOTICE.md)
-- UI wrapper: menus, forms and confirm popups go through here (ox_lib by default, Lation UI optional).
-- client/main.lua and client/placement.lua only call UI.*; notifications always use lib.notify.
-- Note: if the server runs Lation's ox_lib fork, ox_lib itself forwards to lation_ui while it is started.
if not Config.enabled then return end

UI = {}

local useLation = false
if Config.useLationUI then
    if GetResourceState('lation_ui') == 'started' then
        useLation = true
    else
        print('^3[blaze_bossmenu]^7 useLationUI is true but lation_ui is not started. Using ox_lib menus instead.')
    end
end
UI.lation = useLation

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
--- data = { id, title, menu (back to), onExit, onBack, canClose,
---          Lation extras: subtitle, headerIcon, headerIconColor, headerIconAnimation,
---          options = { { title, description, icon, iconColor, disabled, readOnly, arrow, menu, onSelect, args, metadata,
---                        progress, progressColor, colorScheme, iconAnimation ('beat' | 'fade' | 'bounce' | 'shake' | 'spin'),
---                        keybind (Lation: little tag on the right) } } }
--- With Lation UI every extra is used (header icon, coloured icons, animations, coloured progress bars, tags).
--- ox_lib keeps its plain look (progress bars and arrows only); the extras are simply left out.
function UI.registerMenu(data)
    local menu = { id = data.id, title = data.title, menu = data.menu, onExit = data.onExit, onBack = data.onBack, canClose = data.canClose, options = {} }
    for i, o in ipairs(data.options or {}) do
        local opt = {
            title = o.title, description = o.description, icon = o.icon, disabled = o.disabled, readOnly = o.readOnly,
            menu = o.menu, onSelect = o.onSelect, args = o.args, metadata = o.metadata, progress = o.progress, arrow = o.arrow,
            event = o.event, serverEvent = o.serverEvent, -- used by menu items other scripts add (AddBossMenuItem)
        }
        if useLation then -- ox_lib keeps its plain look
            opt.iconColor, opt.iconAnimation, opt.keybind = o.iconColor, o.iconAnimation, o.keybind
            opt.progressColor, opt.colorScheme = o.progressColor, o.colorScheme
        end
        menu.options[i] = opt
    end
    if useLation then
        menu.subtitle = data.subtitle
        menu.headerIcon, menu.headerIconColor, menu.headerIconAnimation = data.headerIcon, data.headerIconColor, data.headerIconAnimation
        return exports.lation_ui:registerMenu(menu)
    end
    return lib.registerContext(menu)
end

--- One palette for the menus, so every screen uses the same colours (Lation icons, tags, progress bars)
UI.color = {
    blue = '#5AA9FF', green = '#3DDC84', amber = '#F0A93B', red = '#E5484D', purple = '#A78BFA',
    teal = '#2DD4BF', pink = '#F472B6', gold = '#F5C542', grey = '#8F99A5',
}

function UI.showMenu(id)
    if useLation then return exports.lation_ui:showMenu(id) end
    return lib.showContext(id)
end

function UI.hideMenu(runOnExit)
    if useLation then return exports.lation_ui:hideMenu(runOnExit == true) end
    return lib.hideContext(runOnExit == true)
end

---------------------------------------------------------------------------
-- Input dialogs
---------------------------------------------------------------------------
--- fields: { { type = 'input'|'textarea'|'number'|'select'|'checkbox', label, description, placeholder, required,
---            default, checked, min, max (number value), minLength, maxLength (text), options = { {value,label} } } }
--- opts:   { allowCancel, submitText, type (Lation button style) }
--- returns values by index, or nil if cancelled. Empty number/select come back as nil in both modes.
function UI.input(title, fields, opts)
    opts = opts or {}
    local rows = {}
    for i, f in ipairs(fields) do
        local r = { type = f.type, label = f.label, description = f.description, placeholder = f.placeholder,
            required = f.required, default = f.default, icon = f.icon, disabled = f.disabled }
        if f.type == 'checkbox' then
            r.checked = f.checked or f.default == true
            r.default = nil
            if useLation then r.default = r.checked end
        elseif f.type == 'number' then
            r.min, r.max = f.min, f.max
        elseif f.type == 'select' then
            r.options = f.options
            if useLation then r.searchable = false end
        elseif f.type == 'input' or f.type == 'textarea' then
            if useLation then
                r.min, r.max = f.minLength, f.maxLength -- Lation: min/max are characters
            else
                r.minLength, r.maxLength = f.minLength, f.maxLength
                if f.type == 'textarea' then r.autosize = true end
            end
        end
        rows[i] = r
    end

    local values
    if useLation then
        values = exports.lation_ui:input({
            title = title, subtitle = opts.subtitle, options = rows, submitText = opts.submitText,
            type = opts.type, cancel = opts.allowCancel ~= false,
        })
    else
        values = lib.inputDialog(title, rows, { allowCancel = opts.allowCancel ~= false, size = opts.size })
    end
    if not values then return nil end
    for i, f in ipairs(fields) do
        local v = values[i]
        if v == '' and (f.type == 'number' or f.type == 'select') then values[i] = nil end
        if f.type == 'checkbox' then values[i] = v == true end
    end
    return values
end

---------------------------------------------------------------------------
-- Confirm popups
---------------------------------------------------------------------------
--- data = { header, content, type = 'error'|'warning'|'info', callout = 'text', icon, confirm = 'label', cancel = 'label' }
--- returns true when confirmed
function UI.confirm(data)
    local labels = { confirm = data.confirm or 'Confirm', cancel = data.cancel or 'Cancel' }
    if useLation then
        return exports.lation_ui:alert({
            header = data.header, content = data.content, type = data.type or 'info', icon = data.icon,
            cancel = true, labels = labels,
            callouts = data.callout and { { description = data.callout, type = data.type == 'error' and 'error' or (data.type == 'warning' and 'warning' or 'info') } } or nil,
        }) == 'confirm'
    end
    return lib.alertDialog({ header = data.header, content = data.content, centered = true, cancel = true, labels = labels }) == 'confirm'
end

--- Close an open input dialog (used when a contract times out)
function UI.closeInput()
    if useLation then return pcall(function() exports.lation_ui:closeInput() end) end
    return lib.closeInputDialog()
end

--- Close an open confirm popup (used when a hire offer times out)
function UI.closeConfirm()
    if useLation then return pcall(function() exports.lation_ui:closeAlert() end) end
    return lib.closeAlertDialog()
end
