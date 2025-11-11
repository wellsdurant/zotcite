local config = require("zotcite.config").get_config()

local M = {}

local vt_citation = function(ns, i, s, e, a)
    if not a then return end
    a = a:gsub("%-", "_")
    local set_m = vim.api.nvim_buf_set_extmark
    set_m(0, ns, i - 1, s - 1, { end_col = e, hl_group = "Ignore", conceal = "" })
    set_m(
        0,
        ns,
        i - 1,
        e,
        { virt_text = { { a, "Identifier" } }, virt_text_pos = "inline" }
    )
end

local vt_citations_md = function(ac, ns, lines)
    local kp = "%[.-%]%(zotero://select/library/items/([0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z])%)"
    local a = ""
    for k, v in pairs(lines) do
        local i = 1
        while true do
            local s, e, key = v:find(kp, i)
            if not s or not e then break end
            a = ac[key]
            vt_citation(ns, k, s, e, a)
            i = e + 1
        end
    end
end

local vt_citations_typ = function(ac, ns, lines)
    local kp = "<[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]>"
    local a = ""
    for k, v in pairs(lines) do
        local i = 1
        while true do
            local s, e = v:find(kp, i)
            if not s or not e then break end
            a = ac[v:sub(s + 1, e - 1)]
            vt_citation(ns, k, s, e, a)
            i = e + 1
        end
    end
end

local vt_citations_tex = function(ac, ns, lines)
    local kp1 = "\\%w*cit.*{"
    local kp2 = "[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]"
    local a = ""
    for k, v in pairs(lines) do
        local i = 1
        while true do
            local s, e = v:find(kp1, i)
            if not s or not e then break end
            local j = e
            local l = v:find("%}", j)
            if not l then l = 1000 end
            while j < l do
                local s2, e2 = v:find(kp2, j)
                if not s2 or not e2 then break end
                a = ac[v:sub(s2, e2)]
                vt_citation(ns, k, s2, e2, a)
                j = e2 + 1
            end
            i = e + 1
        end
    end
end

local vt_citations = function()
    local ac = vim.fn.py3eval("ZotCite.GetAllCitations()")
    local ns = vim.api.nvim_create_namespace("ZCitation")
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    if vim.o.filetype ~= "latex" and vim.o.filetype ~= "rnoweb" then
        vt_citations_md(ac, ns, lines)
    end
    if vim.o.filetype == "typst" then vt_citations_typ(ac, ns, lines) end
    if vim.o.filetype == "tex" or vim.o.filetype == "rnoweb" then
        vt_citations_tex(ac, ns, lines)
    end
end

local hl_zotkeys = function()
    local ns = vim.api.nvim_create_namespace("ZCitation")
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    local kp = "%[(.-)%]%(zotero://select/library/items/[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]%)"
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    local set_m = vim.api.nvim_buf_set_extmark
    for k, v in pairs(lines) do
        local i = 1
        while true do
            local s, e, link_text = v:find(kp, i)
            if not s or not e then break end
            -- Find where the link text ends and URL starts
            local bracket_end = s + #link_text
            -- Highlight the link text
            set_m(0, ns, k - 1, s - 1, { end_col = bracket_end + 1, hl_group = "Identifier" })
            -- Conceal the URL part: ](zotero://...)
            set_m(0, ns, k - 1, bracket_end + 1, { end_col = e, hl_group = "Ignore", conceal = "" })
            i = e + 1
        end
    end
end

M.citations = function()
    if not config.hl_cite_key then return end
    if config.bib_and_vt[vim.o.filetype] then
        vt_citations()
    else
        hl_zotkeys()
    end
end

return M
