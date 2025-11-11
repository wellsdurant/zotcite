local config = require("zotcite.config").get_config()
local ns = vim.api.nvim_create_namespace("ZSeekPreview")

local M = {}

local get_match = function(key)
    local citeptrn = key:gsub(" .*", "")
    local refs = vim.fn.py3eval(
        'ZotCite.GetMatch("'
            .. citeptrn
            .. '", "'
            .. vim.fn.escape(vim.fn.expand("%:p"), "\\")
            .. '", True)'
    )
    if #refs == 0 then
        vim.schedule(
            function() vim.api.nvim_echo({ { "No matches found." } }, false, {}) end
        )
    end
    return refs
end

M.print = function(ref)
    local msg = {
        { ref.value.title, "Title" },
        { " " },
        { ref.value.year, "Number" },
        { " " },
        { ref.value.alastnm, "Identifier" },
    }
    vim.schedule(function() vim.api.nvim_echo(msg, false, {}) end)
end

local format_preview = function(v)
    local parts = {}
    local hl = {}
    local pos = 0

    -- (abbreviation) if present
    if v.abbreviation and v.abbreviation ~= "" then
        local abbr_text = "(" .. v.abbreviation .. ") "
        table.insert(parts, abbr_text)
        table.insert(hl, { g = "String", s = pos, e = pos + #abbr_text })
        pos = pos + #abbr_text
    end

    -- title
    local title = v.title or "Untitled"
    table.insert(parts, title .. ", ")
    table.insert(hl, { g = "Title", s = pos, e = pos + #title })
    pos = pos + #title + 2

    -- year
    local year = v.year or "????"
    table.insert(parts, year .. ", ")
    table.insert(hl, { g = "Number", s = pos, e = pos + #year })
    pos = pos + #year + 2

    -- author
    local alist = {}
    local authors
    if v.author then
        if #v.author > 5 then
            authors = v.author[1][1] .. ", " .. v.author[1][2] .. " and others"
        else
            for _, n in pairs(v.author) do
                table.insert(alist, n[1] .. ", " .. n[2])
            end
            authors = table.concat(alist, "; ")
        end
    else
        authors = "Unknown"
    end
    table.insert(parts, authors)
    table.insert(hl, { g = "Identifier", s = pos, e = pos + #authors })
    pos = pos + #authors

    -- (organization) if present
    if v.organization and v.organization ~= "" then
        local org_text = " (" .. v.organization .. ")"
        table.insert(parts, org_text)
        table.insert(hl, { g = "Comment", s = pos, e = pos + #org_text })
        pos = pos + #org_text
    end

    -- publication
    local ptitle = v.publicationTitle or "????"
    -- Append PublicationNote if present
    if v.publicationnote and v.publicationnote ~= "" then
        ptitle = ptitle .. " (" .. v.publicationnote .. ")"
    end
    local pub_text = ", " .. ptitle
    table.insert(parts, pub_text)
    table.insert(hl, { g = "Include", s = pos + 2, e = pos + 2 + #ptitle })
    pos = pos + #pub_text

    -- abstract
    local abstract = v.abstract or "No abstract available."
    local txt = table.concat(parts) .. "\n\n" .. abstract .. "\n"

    return txt, hl
end

--- Use telescope to find and select a reference
---@param key string Pattern to search
---@param cb function Callback function
M.refs = function(key, cb)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local sorters = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")
    local entry_display = require("telescope.pickers.entry_display")
    local mtchs = get_match(key)
    local references = {}

    -- Calculate column widths
    local title_width = 50  -- Title width
    local year_width = 4  -- Year width
    local author_width = 15  -- Author width
    local org_width = 10  -- Organization width
    local pub_width = 15  -- Publication width

    for _, v in pairs(mtchs) do
        -- Get base publication title
        local pub_base = v.publicationTitle
            or v.bookTitle
            or v.proceedingsTitle
            or v.conferenceName
            or v.programTitle
            or v.blogTitle
            or v.code
            or v.dictionaryTitle
            or v.encyclopediaTitle
            or v.forumTitle
            or v.websiteTitle
            or v.seriesTitle
            or ""

        -- Build display string with PublicationNote for list view
        local pub_display = pub_base
        if v.publicationnote and v.publicationnote ~= "" then
            pub_display = pub_display .. " (" .. v.publicationnote .. ")"
        end

        local author_len = #(v.alastnm or "")
        local org_len = #(v.organization or "")
        local pub_len = #pub_display

        if author_len > author_width then author_width = author_len end
        if org_len > org_width then org_width = org_len end
        if pub_len > pub_width then pub_width = pub_len end

        table.insert(references, {
            display = (v.title or "") .. " " .. (v.year or "") .. " " .. (v.alastnm or "") .. " " .. (v.organization or "") .. " " .. pub_display,
            etype = v.etype,
            sort_key = v[config.sort_key] or "0000-00-00 0000",
            publicationTitle = pub_base,  -- Store base without note for preview
            author = v.author
                or v.artist
                or v.performer
                or v.director
                or v.composer
                or v.sponsor
                or v.contributor
                or v.interviewee
                or v.cartographer
                or v.inventor
                or v.podcaster
                or v.presenter
                or v.programmer
                or v.recipient
                or v.editor
                or v.seriesEditor
                or v.translator
                or {},
            alastnm = v.alastnm or "",
            year = v.year or "",
            title = v.title or "",
            abstract = v.abstractNote or "",
            key = v.zotkey or "",
            cite = v.citekey or "",
            abbreviation = v.abbreviation or "",
            organization = v.organization or "",
            publicationnote = v.publicationnote or "",
        })
    end

    -- Apply width limits
    if author_width > 30 then author_width = 30 end
    if org_width > 20 then org_width = 20 end
    if pub_width > 30 then pub_width = 30 end

    table.sort(references, function(a, b) return (a.sort_key > b.sort_key) end)

    pickers
        .new({}, {
            prompt_title = "Search pattern",
            results_title = "Zotero references",
            finder = finders.new_table({
                results = references,
                entry_maker = function(entry)
                    local displayer = entry_display.create({
                        separator = " ",
                        items = {
                            { width = title_width }, -- Title
                            { width = year_width }, -- Year
                            { width = author_width }, -- Author
                            { width = org_width }, -- Organization
                            { remaining = true }, -- Publication
                        },
                    })
                    return {
                        value = entry,
                        display = function(e)
                            -- Build publication display with note if present
                            local pub_text = e.value.publicationTitle or ""
                            if e.value.publicationnote and e.value.publicationnote ~= "" then
                                pub_text = pub_text .. " (" .. e.value.publicationnote .. ")"
                            end
                            -- Prepend abbreviation to title if present
                            local title_text = e.value.title or ""
                            if e.value.abbreviation and e.value.abbreviation ~= "" then
                                title_text = "(" .. e.value.abbreviation .. ") " .. title_text
                            end
                            return displayer({
                                { title_text, "Title" },
                                { e.value.year or "", "Number" },
                                { e.value.alastnm or "", "Identifier" },
                                { e.value.organization or "", "Comment" },
                                { pub_text, "Include" },
                            })
                        end,
                        ordinal = (entry.abbreviation ~= "" and "(" .. entry.abbreviation .. ") " or "") .. entry.display,
                    }
                end,
            }),
            sorter = sorters.generic_sorter({}),
            previewer = previewers.new_buffer_previewer({
                define_preview = function(self, entry, _)
                    local bufnr = self.state.bufnr
                    local preview_text, hl = format_preview(entry.value)
                    vim.api.nvim_buf_set_lines(
                        bufnr,
                        0,
                        -1,
                        false,
                        vim.split(preview_text, "\n")
                    )
                    for _, h in pairs(hl) do
                        if vim.fn.has("nvim-0.11") == 1 then
                            vim.hl.range(bufnr, ns, h.g, { 0, h.s }, { 0, h.e }, {})
                        else
                            vim.api.nvim_buf_add_highlight(bufnr, -1, h.g, 0, h.s, h.e)
                        end
                    end
                end,
            }),
            attach_mappings = function(prompt_bufnr, map)
                map({ "i", "n" }, "<CR>", function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    -- Handle the selected reference here
                    cb(selection)
                end)
                return true
            end,
        })
        :find()
end

--  text wrapping in the preview window
vim.api.nvim_create_autocmd("User", {
    pattern = "TelescopePreviewerLoaded",
    callback = function()
        vim.wo.wrap = true
        vim.wo.linebreak = true
    end,
})

return M
