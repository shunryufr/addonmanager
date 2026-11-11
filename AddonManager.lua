--[[
    AddonManager - Windower 4 (FFXI)
    Interface cliquable pour charger / decharger les addons et les plugins.

    Installation : windower/addons/AddonManager/AddonManager.lua
    Lancement    : //lua load addonmanager
    Commandes    : //am            afficher / cacher la fenetre
                   //am collapse   replier / deplier la fenetre
                   //am filter x   filtrer la liste (//am filter pour effacer)
                   //am refresh    rescanner les dossiers addons / plugins
                   //am reset      relire l'autoload (scripts/init.txt, scripts/autoload, exec) et recalculer l'etat
                   //am debug      afficher les fichiers d'autoload lus et les lignes non reconnues
                   //am mouse      afficher les codes d'evenements souris (diagnostic clic droit)
                   //am sc         lister les shortcuts
                   //am sc add <nom> = <commande>
                   //am sc edit <n> [<nom> =] <commande>
                   //am sc del <n> | move <n> <pos> | run <n> | reload
                   Les shortcuts sont dans addons/AddonManager/data/shortcuts.txt (une ligne : nom|commande),
                   modifiable aussi a la main puis //am sc reload.
                   //am pos x y    deplacer la fenetre
    Onglets      : Addons / Plugins / Shortcuts (raccourcis de commandes editables)
    Souris       : clic gauche sur une ligne = load / unload
                   clic droit sur un addon    = reload ; sur un shortcut = l'editer
                   bouton [-] / [+] de la barre du haut (ou clic droit sur la barre) = replier / deplier
                   molette = changer de page, barre du haut = deplacer
]]

_addon.name     = 'AddonManager'
_addon.author   = 'Claude'
_addon.version  = '1.5.0'
_addon.commands = {'am', 'addonmanager'}

local config = require('config')
local texts  = require('texts')
local images = require('images')

local defaults = {
    pos       = {x = 120, y = 120},
    visible   = true,
    collapsed = false,
}
local settings = config.load(defaults)

---------------------------------------------------------------------
-- Dimensions
---------------------------------------------------------------------
local W, HEAD_H, TAB_H, ROW_H, ROWS, FOOT_H, STATUS_H = 300, 26, 24, 20, 14, 26, 18
local H = HEAD_H + TAB_H + ROWS * ROW_H + FOOT_H + STATUS_H

---------------------------------------------------------------------
-- Etat
---------------------------------------------------------------------
local tab    = 'addon'            -- 'addon', 'plugin' ou 'sc'
local page   = 1
local filter = ''
local hover  = nil
local drag   = nil
local lists  = {addon = {}, plugin = {}}
local canon  = {addon = {}, plugin = {}}   -- minuscule -> nom reel
local loaded = {addon = {}, plugin = {}}   -- cles en minuscules
local autoload = {}                        -- { {name=, kind=}, ... } dans l'ordre du script
local self_name = _addon.name:lower()

local function say(msg)
    windower.add_to_chat(207, '[AddonManager] ' .. msg)
end

---------------------------------------------------------------------
-- Autoload : lecture de scripts/init.txt (et des scripts lances par exec)
---------------------------------------------------------------------
local function auto_add(name, kind)
    local l = name:lower()
    for _, e in ipairs(autoload) do
        if e.kind == kind and e.name:lower() == l then return end
    end
    autoload[#autoload + 1] = {name = name, kind = kind}
end

local function auto_remove(name, kind)
    local l = name:lower()
    for i, e in ipairs(autoload) do
        if e.kind == kind and e.name:lower() == l then
            table.remove(autoload, i)
            return
        end
    end
end

local report = {}   -- diagnostic : fichiers lus, entrees trouvees, lignes non reconnues

local function guess_kind(name)
    local base = windower.windower_path
    if windower.dir_exists(base .. 'addons/' .. name) then return 'addon' end
    if windower.file_exists(base .. 'plugins/' .. name .. '.dll') then return 'plugin' end
    return 'addon'
end

local function process_script(path, depth, seen, bare)
    if depth > 5 or seen[path:lower()] then return end
    seen[path:lower()] = true
    local f = io.open(path, 'r')
    if not f then return end
    local rep = {path = path, found = 0, unparsed = {}}
    report[#report + 1] = rep

    local function add(name, kind)
        loaded[kind][name:lower()] = true
        auto_add(name, kind)
        rep.found = rep.found + 1
    end

    for line in f:lines() do
        local l = (line:gsub('^%s+', ''):gsub('%s+$', ''))
        if l ~= '' and not l:find('^[#;]') and not l:find('^%-%-') then
            for piece in (l .. ';'):gmatch('([^;]*);') do
                local cmd = piece:gsub('^%s+', ''):gsub('%s+$', ''):gsub('^//', ''):gsub('^/', '')
                local orig, rest = cmd:match('^(%S+)%s*(.*)$')
                if orig then
                    local w1 = orig:lower()
                    if w1 == 'lua' then
                        local sub, name = rest:match('^(%S+)%s+(%S+)')
                        sub = sub and sub:lower()
                        if sub == 'load' or sub == 'l' or sub == 'reload' or sub == 'r' then
                            add(name, 'addon')
                        elseif sub == 'unload' or sub == 'u' then
                            loaded.addon[name:lower()] = nil
                            auto_remove(name, 'addon')
                        end
                    elseif w1 == 'load' and rest ~= '' then
                        add(rest:match('^(%S+)'), 'plugin')
                    elseif w1 == 'unload' and rest ~= '' then
                        local name = rest:match('^(%S+)')
                        loaded.plugin[name:lower()] = nil
                        auto_remove(name, 'plugin')
                    elseif w1 == 'exec' and rest ~= '' then
                        local file = rest:match('^(%S+)')
                        if not file:find('%.[%w]+$') then file = file .. '.txt' end
                        process_script(windower.windower_path .. 'scripts/' .. file, depth + 1, seen, false)
                    elseif bare and rest == '' and orig:find('^[%w_%.%-]+$') and w1 ~= 'wait' then
                        -- fichier d'autoload : simple liste de noms
                        add(orig, guess_kind(orig))
                    elseif #rep.unparsed < 10 then
                        rep.unparsed[#rep.unparsed + 1] = cmd
                    end
                end
            end
        end
    end
    f:close()
end

-- scripts/autoload peut etre un fichier ou un dossier contenant des fichiers de config
local function process_autoload(seen)
    local base = windower.windower_path .. 'scripts/'
    local path = base .. 'autoload'

    if windower.dir_exists(path) then
        local function scan_dir(dir, level)
            local entries = windower.get_dir(dir) or {}
            table.sort(entries, function(a, b) return a:lower() < b:lower() end)
            for _, e in ipairs(entries) do
                local full = dir .. '/' .. e
                if windower.dir_exists(full) then
                    if level < 2 then scan_dir(full, level + 1) end
                else
                    process_script(full, 1, seen, true)
                end
            end
        end
        scan_dir(path, 1)
    else
        for _, candidate in ipairs({path, path .. '.txt', path .. '.cfg', path .. '.conf', path .. '.ini'}) do
            process_script(candidate, 1, seen, true)
        end
    end
end

local function read_init_state()
    loaded   = {addon = {}, plugin = {}}
    autoload = {}
    report   = {}
    local seen = {}
    process_script(windower.windower_path .. 'scripts/init.txt', 1, seen, false)
    process_autoload(seen)
end

local function print_report()
    say(('Autoload : %d entree(s).'):format(#autoload))
    if #report == 0 then
        say('Aucun fichier lu (scripts/init.txt et scripts/autoload introuvables).')
    end
    for _, r in ipairs(report) do
        local short = r.path:gsub('^.*[/\\]scripts[/\\]', 'scripts/')
        say(('%s : %d trouve(s), %d ligne(s) non reconnue(s)'):format(short, r.found, #r.unparsed))
        for _, u in ipairs(r.unparsed) do say('   ? ' .. u) end
    end
end

---------------------------------------------------------------------
-- Scan des dossiers
---------------------------------------------------------------------
local function sort_ci(list)
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
end

local function scan()
    local base = windower.windower_path

    local addons = {}
    local dir = base .. 'addons/'
    for _, e in ipairs(windower.get_dir(dir) or {}) do
        if e:lower() ~= self_name
            and windower.dir_exists(dir .. e)
            and windower.file_exists(dir .. e .. '/' .. e .. '.lua') then
            addons[#addons + 1] = e
        end
    end

    local plugins = {}
    dir = base .. 'plugins/'
    for _, e in ipairs(windower.get_dir(dir) or {}) do
        local n = e:match('^(.+)%.[dD][lL][lL]$')
        if n then plugins[#plugins + 1] = n end
    end

    lists.addon, lists.plugin = addons, plugins

    -- les entrees de l'autoload doivent toujours apparaitre dans les listes
    for _, e in ipairs(autoload) do
        local present = false
        for _, n in ipairs(lists[e.kind]) do
            if n:lower() == e.name:lower() then present = true break end
        end
        if not present and e.name:lower() ~= self_name then
            lists[e.kind][#lists[e.kind] + 1] = e.name
        end
    end

    sort_ci(lists.addon)
    sort_ci(lists.plugin)

    canon = {addon = {}, plugin = {}}
    for _, k in ipairs({'addon', 'plugin'}) do
        for _, n in ipairs(lists[k]) do canon[k][n:lower()] = n end
    end
end

---------------------------------------------------------------------
-- Shortcuts (commandes personnalisees et editables)
---------------------------------------------------------------------
local SC_FILE = windower.addon_path .. 'data/shortcuts.txt'
local shortcuts = {}   -- { {name=, cmd=}, ... }

local function trim(str)
    return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function save_shortcuts()
    windower.create_dir(windower.addon_path .. 'data')
    local f = io.open(SC_FILE, 'w')
    if not f then
        say('Impossible d\'ecrire ' .. SC_FILE)
        return
    end
    for _, sc in ipairs(shortcuts) do
        f:write(sc.name, '|', sc.cmd, '\n')
    end
    f:close()
end

local function load_shortcuts()
    shortcuts = {}
    local f = io.open(SC_FILE, 'r')
    if not f then
        shortcuts = {
            {name = 'Reload GearSwap',   cmd = 'lua reload gearswap'},
            {name = 'Liste des addons',  cmd = 'lua list'},
        }
        save_shortcuts()
        return
    end
    for line in f:lines() do
        local n, c = line:match('^([^|]+)|(.+)$')
        if n then
            shortcuts[#shortcuts + 1] = {name = trim(n), cmd = trim(c)}
        end
    end
    f:close()
end

local function run_shortcut(i)
    local sc = shortcuts[i]
    if sc then windower.send_command(sc.cmd) end
end

local function set_input(text)
    if windower.chat and windower.chat.set_input then
        windower.chat.set_input(text)
    else
        say('Tape : ' .. text)
    end
end

-- liste affichee : tableau de {name=, kind=} (kind = 'addon', 'plugin' ou 'sc')
local function get_items()
    local out, f = {}, filter:lower()
    if tab == 'sc' then
        for i, sc in ipairs(shortcuts) do
            if f == '' or sc.name:lower():find(f, 1, true) then
                out[#out + 1] = {name = sc.name, kind = 'sc', idx = i, cmd = sc.cmd}
            end
        end
    else
        for _, n in ipairs(lists[tab]) do
            if f == '' or n:lower():find(f, 1, true) then
                out[#out + 1] = {name = n, kind = tab}
            end
        end
    end
    return out
end

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------
local function toggle(name, kind)
    local key = name:lower()
    local on = loaded[kind][key]
    if kind == 'addon' then
        windower.send_command(('lua %s %s'):format(on and 'unload' or 'load', name))
    else
        windower.send_command(('%s %s'):format(on and 'unload' or 'load', name))
    end
    loaded[kind][key] = (not on) or nil
end

local function reload(name)
    windower.send_command('lua reload ' .. name)
    loaded.addon[name:lower()] = true
end

---------------------------------------------------------------------
-- Objets graphiques
---------------------------------------------------------------------
local all = {}

local function new_rect()
    local img = images.new({
        pos   = {x = 0, y = 0},
        color = {alpha = 230, red = 20, green = 20, blue = 30},
        size  = {width = 10, height = 10},
        draggable = false,
    })
    img:hide()
    all[#all + 1] = img
    return img
end

local function new_text(size, bold)
    local t = texts.new('', {
        pos   = {x = 0, y = 0},
        bg    = {visible = false},
        flags = {draggable = false, bold = bold or false},
        text  = {
            size = size or 10,
            font = 'Arial',
            stroke = {width = 1, alpha = 200, red = 0, green = 0, blue = 0},
        },
    })
    t:color(255, 255, 255)
    t:hide()
    all[#all + 1] = t
    return t
end

-- ordre de creation = ordre d'empilement des rectangles
local ui = {}
ui.bg      = new_rect()
ui.head    = new_rect()
ui.close   = new_rect()
ui.mini    = new_rect()
ui.tab_addon, ui.tab_plugin, ui.tab_sc = new_rect(), new_rect(), new_rect()
ui.rows = {}
for i = 1, ROWS do ui.rows[i] = {img = new_rect()} end
ui.foot    = new_rect()
ui.prev, ui.next, ui.refresh = new_rect(), new_rect(), new_rect()

ui.title   = new_text(11, true)
ui.close_t = new_text(11, true)
ui.mini_t  = new_text(11, true)
ui.tab_addon_t, ui.tab_plugin_t, ui.tab_sc_t = new_text(9, true), new_text(9, true), new_text(9, true)
for i = 1, ROWS do
    ui.rows[i].state = new_text(9, true)
    ui.rows[i].name  = new_text(10)
end
ui.prev_t, ui.next_t, ui.refresh_t = new_text(10, true), new_text(10, true), new_text(10, true)
ui.info    = new_text(10)
ui.status  = new_text(8)

local C = {
    bg      = {12, 12, 20, 225},
    head    = {45, 70, 125, 240},
    tab_on  = {60, 90, 160, 240},
    tab_off = {30, 30, 45, 235},
    tab_h   = {45, 45, 70, 240},
    row_on  = {25, 85, 45, 235},
    row_on_h  = {40, 120, 65, 240},
    row_off = {30, 30, 44, 235},
    row_off_h = {55, 55, 80, 240},
    btn     = {45, 45, 70, 240},
    btn_h   = {75, 75, 115, 240},
    close_h = {170, 50, 50, 240},
    foot    = {20, 20, 32, 235},
}

local function rect(img, r, c)
    img:pos(r.x, r.y)
    img:size(r.w, r.h)
    img:color(c[1], c[2], c[3])
    img:alpha(c[4])
    img:show()
end

local function label(t, str, x, y)
    t:text(str)
    t:pos(x, y)
    t:show()
end

---------------------------------------------------------------------
-- Geometrie (utilisee pour l'affichage ET pour les clics)
---------------------------------------------------------------------
local function geom()
    local x, y = settings.pos.x, settings.pos.y
    local rows_y = y + HEAD_H + TAB_H
    local foot_y = rows_y + ROWS * ROW_H
    local tw = math.floor((W - 16) / 3)
    local ty = y + HEAD_H + 2
    local g = {
        window     = {x = x, y = y, w = W, h = settings.collapsed and HEAD_H or H},
        head       = {x = x, y = y, w = W - 54, h = HEAD_H},
        mini       = {x = x + W - 52, y = y + 3, w = 22, h = HEAD_H - 6},
        close      = {x = x + W - 26, y = y + 3, w = 22, h = HEAD_H - 6},
        tab_addon  = {x = x + 4, y = ty, w = tw, h = TAB_H - 4},
        tab_plugin = {x = x + 8 + tw, y = ty, w = tw, h = TAB_H - 4},
        tab_sc     = {x = x + 12 + 2 * tw, y = ty, w = tw, h = TAB_H - 4},
        foot       = {x = x, y = foot_y, w = W, h = FOOT_H},
        prev       = {x = x + 6, y = foot_y + 3, w = 34, h = FOOT_H - 6},
        next       = {x = x + 130, y = foot_y + 3, w = 34, h = FOOT_H - 6},
        refresh    = {x = x + W - 86, y = foot_y + 3, w = 80, h = FOOT_H - 6},
    }
    for i = 1, ROWS do
        g['row' .. i] = {x = x + 2, y = rows_y + (i - 1) * ROW_H, w = W - 4, h = ROW_H - 1}
    end
    return g
end

local order = {'close', 'mini', 'tab_addon', 'tab_plugin', 'tab_sc', 'prev', 'next', 'refresh', 'head'}
for i = 1, ROWS do order[#order + 1] = 'row' .. i end

local function inside(r, x, y)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function hit(g, x, y)
    for _, id in ipairs(order) do
        if not (settings.collapsed and id ~= 'close' and id ~= 'mini' and id ~= 'head')
            and inside(g[id], x, y) then
            return id
        end
    end
end

---------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------
local tab_names = {addon = 'Addons', plugin = 'Plugins', sc = 'Shortcuts'}

local function draw()
    if not settings.visible then
        for _, o in ipairs(all) do o:hide() end
        return
    end

    local g = geom()
    local x, y = settings.pos.x, settings.pos.y
    local items = get_items()
    local pages = math.max(1, math.ceil(#items / ROWS))
    if page > pages then page = pages end
    if page < 1 then page = 1 end

    rect(ui.bg, g.window, C.bg)
    rect(ui.head, {x = x, y = y, w = W, h = HEAD_H}, C.head)
    label(ui.title, 'Addon Manager' .. (settings.collapsed and '  [+]' or ''), x + 8, y + 5)
    rect(ui.close, g.close, hover == 'close' and C.close_h or C.btn)
    label(ui.close_t, 'X', g.close.x + 7, g.close.y + 2)
    rect(ui.mini, g.mini, hover == 'mini' and C.btn_h or C.btn)
    label(ui.mini_t, settings.collapsed and '+' or '-', g.mini.x + 8, g.mini.y + 2)

    if settings.collapsed then
        for _, o in ipairs(all) do
            if o ~= ui.bg and o ~= ui.head and o ~= ui.close and o ~= ui.mini
                and o ~= ui.title and o ~= ui.close_t and o ~= ui.mini_t then
                o:hide()
            end
        end
        return
    end

    for _, k in ipairs({'addon', 'plugin', 'sc'}) do
        local id = 'tab_' .. k
        local c = (tab == k) and C.tab_on or (hover == id and C.tab_h or C.tab_off)
        local n = (k == 'sc') and #shortcuts or #lists[k]
        rect(ui[id], g[id], c)
        label(ui[id .. '_t'], tab_names[k] .. ' (' .. n .. ')', g[id].x + 5, g[id].y + 3)
    end

    for i = 1, ROWS do
        local row = ui.rows[i]
        local item = items[(page - 1) * ROWS + i]
        if item then
            local sc = (item.kind == 'sc')
            local on = (not sc) and loaded[item.kind][item.name:lower()]
            local h = (hover == 'row' .. i)
            local c
            if on then c = h and C.row_on_h or C.row_on
            else       c = h and C.row_off_h or C.row_off end
            local r = g['row' .. i]
            rect(row.img, r, c)
            local st
            if sc then st = '\\cs(120,180,255)GO\\cr'
            elseif on then st = '\\cs(110,255,130)ON\\cr'
            else st = '\\cs(255,110,110)OFF\\cr' end
            label(row.state, st, r.x + 6, r.y + 4)
            label(row.name, item.name, r.x + 42, r.y + 3)
        else
            row.img:hide(); row.state:hide(); row.name:hide()
        end
    end

    rect(ui.foot, g.foot, C.foot)
    rect(ui.prev, g.prev, hover == 'prev' and C.btn_h or C.btn)
    rect(ui.next, g.next, hover == 'next' and C.btn_h or C.btn)
    rect(ui.refresh, g.refresh, hover == 'refresh' and C.btn_h or C.btn)
    label(ui.prev_t, '<', g.prev.x + 13, g.prev.y + 2)
    label(ui.next_t, '>', g.next.x + 13, g.next.y + 2)
    label(ui.refresh_t, tab == 'sc' and '+ Add' or 'Refresh', g.refresh.x + 14, g.refresh.y + 2)
    label(ui.info, ('%d / %d'):format(page, pages), g.prev.x + 46, g.prev.y + 2)

    local status
    if tab == 'sc' and hover and hover:find('^row') then
        local it = items[(page - 1) * ROWS + tonumber(hover:match('%d+'))]
        if it then status = it.cmd end
    end
    status = status
        or (filter ~= '' and ('Filtre : ' .. filter .. '  (' .. #items .. ')'))
        or (tab == 'sc' and 'Clic G : lancer  |  Clic D : editer')
        or 'Clic G : load/unload  |  Clic D : reload'
    if #status > 52 then status = status:sub(1, 49) .. '...' end
    label(ui.status, status, x + 8, g.foot.y + FOOT_H + 2)
end

---------------------------------------------------------------------
-- Souris
---------------------------------------------------------------------
local function row_item(id)
    return get_items()[(page - 1) * ROWS + tonumber(id:match('%d+'))]
end

local rdown_seen = false   -- vrai des qu'un evenement "clic droit enfonce" (3) a ete recu
local mdebug     = false

local function right_click(id)
    if id == 'head' then
        -- clic droit sur la barre du haut : replier / deplier la fenetre
        settings.collapsed = not settings.collapsed
        config.save(settings)
    elseif id and id:find('^row') then
        local item = row_item(id)
        if item then
            if item.kind == 'sc' then
                set_input(('//am sc edit %d %s = %s'):format(item.idx, item.name, item.cmd))
            elseif item.kind == 'addon' then
                reload(item.name)
                say('reload ' .. item.name)
            end
        end
    end
    draw()
end

windower.register_event('mouse', function(mtype, x, y, delta, blocked)
    if blocked or not settings.visible then return end

    if mtype == 3 then rdown_seen = true end

    -- deplacement de la fenetre
    if drag then
        if mtype == 0 then
            settings.pos.x = x - drag.dx
            settings.pos.y = y - drag.dy
            draw()
            return true
        elseif mtype == 2 then
            drag = nil
            config.save(settings)
            return true
        end
    end

    local g = geom()
    local id = hit(g, x, y)

    if mtype == 0 then
        if id ~= hover then
            hover = id
            draw()
        end
        return
    end

    if not inside(g.window, x, y) then return end

    if mdebug then
        say(('mouse type=%d x=%d y=%d zone=%s'):format(mtype, x, y, tostring(id)))
    end

    if mtype == 1 then -- clic gauche
        if id == 'close' then
            settings.visible = false
            config.save(settings)
        elseif id == 'mini' then
            settings.collapsed = not settings.collapsed
            config.save(settings)
        elseif id == 'head' then
            drag = {dx = x - settings.pos.x, dy = y - settings.pos.y}
        elseif id == 'tab_addon' or id == 'tab_plugin' or id == 'tab_sc' then
            tab = id:sub(5)
            page = 1
        elseif id == 'prev' then
            page = page - 1
        elseif id == 'next' then
            page = page + 1
        elseif id == 'refresh' then
            if tab == 'sc' then
                set_input('//am sc add Nom = commande')
            else
                scan()
            end
        elseif id and id:find('^row') then
            local item = row_item(id)
            if item then
                if item.kind == 'sc' then
                    run_shortcut(item.idx)
                else
                    toggle(item.name, item.kind)
                end
            end
        end
        draw()
        return true

    elseif mtype == 3 then -- clic droit (enfonce)
        right_click(id)
        return true

    elseif mtype == 4 then -- clic droit (relache)
        -- secours : si Windower n'envoie jamais l'evenement 3, on agit au relachement
        if not rdown_seen then right_click(id) end
        return true

    elseif mtype == 2 then -- relachement du clic gauche
        return true

    elseif mtype == 10 then -- molette
        page = page + (delta > 0 and -1 or 1)
        draw()
        return true
    end
end)

---------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------
local function sc_command(args)
    local sub = (table.remove(args, 1) or 'list'):lower()
    local rest = table.concat(args, ' ')

    if sub == 'list' then
        if #shortcuts == 0 then say('Aucun shortcut.') end
        for i, sc in ipairs(shortcuts) do
            say(('%d. %s = %s'):format(i, sc.name, sc.cmd))
        end
        return
    elseif sub == 'run' then
        run_shortcut(tonumber(rest) or 0)
        return
    elseif sub == 'reload' then
        load_shortcuts()
        say(#shortcuts .. ' shortcut(s) relu(s).')
        return
    elseif sub == 'add' then
        local n, c = rest:match('^(.-)%s*=%s*(.+)$')
        if not n or n == '' then
            say('Usage : //am sc add <nom> = <commande>')
            return
        end
        shortcuts[#shortcuts + 1] = {name = n:gsub('|', '/'), cmd = c}
        say(('Ajoute #%d : %s'):format(#shortcuts, n))
    elseif sub == 'edit' then
        local i, r = rest:match('^(%d+)%s+(.+)$')
        i = tonumber(i)
        if not i or not shortcuts[i] then
            say('Usage : //am sc edit <n> [<nom> =] <commande>')
            return
        end
        local n, c = r:match('^(.-)%s*=%s*(.+)$')
        if n and n ~= '' then
            shortcuts[i].name, shortcuts[i].cmd = (n:gsub('|', '/')), c
        else
            shortcuts[i].cmd = r
        end
        say(('Modifie #%d'):format(i))
    elseif sub == 'del' or sub == 'remove' then
        local i = tonumber(rest)
        if not i or not shortcuts[i] then
            say('Usage : //am sc del <n>')
            return
        end
        say('Supprime : ' .. shortcuts[i].name)
        table.remove(shortcuts, i)
    elseif sub == 'move' then
        local i, j = rest:match('^(%d+)%s+(%d+)$')
        i, j = tonumber(i), tonumber(j)
        if not i or not j or not shortcuts[i] or j < 1 or j > #shortcuts then
            say('Usage : //am sc move <n> <nouvelle position>')
            return
        end
        table.insert(shortcuts, j, table.remove(shortcuts, i))
    else
        say('//am sc [list | add <nom> = <cmd> | edit <n> [<nom> =] <cmd> | del <n> | move <n> <pos> | run <n> | reload]')
        return
    end
    save_shortcuts()
end

windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or 'toggle'

    if cmd == 'toggle' then
        settings.visible = not settings.visible
    elseif cmd == 'show' then
        settings.visible = true
    elseif cmd == 'hide' then
        settings.visible = false
    elseif cmd == 'collapse' then
        settings.collapsed = not settings.collapsed
    elseif cmd == 'filter' or cmd == 'f' then
        filter = table.concat(args, ' ')
        page = 1
    elseif cmd == 'refresh' then
        scan()
    elseif cmd == 'reset' then
        read_init_state()
        scan()
        print_report()
    elseif cmd == 'debug' then
        print_report()
    elseif cmd == 'mouse' then
        mdebug = not mdebug
        say('Debug souris : ' .. (mdebug and 'ON (clique dans la fenetre)' or 'OFF'))
    elseif cmd == 'sc' or cmd == 'shortcut' or cmd == 'shortcuts' then
        sc_command(args)
    elseif cmd == 'pos' and tonumber(args[1]) and tonumber(args[2]) then
        settings.pos.x, settings.pos.y = tonumber(args[1]), tonumber(args[2])
    else
        say('//am [show|hide|collapse] | filter <texte> | refresh | reset | debug | mouse | sc ... | pos <x> <y>')
        return
    end

    config.save(settings)
    draw()
end)

---------------------------------------------------------------------
-- Init / cleanup
---------------------------------------------------------------------
windower.register_event('load', function()
    read_init_state()
    scan()
    load_shortcuts()
    draw()
end)

windower.register_event('unload', function()
    for _, o in ipairs(all) do o:destroy() end
end)
