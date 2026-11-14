local function jump_to_section(heading)
  return function()
    vim.fn.search("^" .. heading, "cw")
  end
end

local function focus_editing_window()
  local api = vim.api
  local tabs = api.nvim_list_tabpages()
  local current = api.nvim_get_current_tabpage()
  local previous = tabs[vim.fn.tabpagenr("#")] or current
  -- Prefer a split beside Neogit, then the previous tab, then other tabs.
  for _, tab in ipairs(vim.list_extend({ current, previous }, tabs)) do
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      local buf = api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local normal = vim.bo[buf].buftype == "" and not vim.startswith(ft, "Neogit")
      local dashboard = ft == "snacks_dashboard"
      if api.nvim_win_get_config(win).relative == "" and (normal or dashboard) then
        api.nvim_set_current_tabpage(tab)
        api.nvim_set_current_win(win)
        return true
      end
    end
  end
  return false
end

local function open_file_keep_status()
  local status = require("neogit.buffers.status").instance()
  local item = status.buffer.ui:get_item_under_cursor()
  if not item or not item.absolute_path then
    require("neogit.buffers.status.actions").n_goto_file(status)()
    return
  end

  if status:has_submodule(item.absolute_path) then
    require("neogit").open({ cwd = item.absolute_path, kind = "tab" })
    return
  end

  local jump = require("neogit.lib.jump")
  local cursor = { 1, 0 }
  -- Match GoToFile's translation from a diff row to the working file's line.
  if rawget(item, "diff") then
    local line = status.buffer:cursor_line()
    for _, hunk in ipairs(item.diff.hunks) do
      if line >= hunk.first and line <= hunk.last then
        cursor = { jump.adjust_row(hunk.disk_from, line - hunk.first, hunk.lines, "-"), 0 }
        break
      end
    end
  end

  vim.schedule(function()
    if not focus_editing_window() then
      vim.cmd("tabnew")
    end
    jump.open("edit", item.absolute_path, cursor)
  end)
end

return {
  {
    "NeogitOrg/neogit",
    lazy = true,
    dependencies = {
      "nvim-lua/plenary.nvim", -- required
      {
        "dlyongemallo/diffview-plus.nvim",
        version = "*",
        main = "diffview",
        opts = {},
      },

      "nvim-telescope/telescope.nvim",
    },
    config = function()
      require("neogit").setup({
        disable_signs = false,
        integrations = { diffview = true },
        mappings = {
          status = {
            ["<cr>"] = open_file_keep_status,
            ["<leader>ju"] = jump_to_section("Unstaged changes"),
            ["<leader>js"] = jump_to_section("Staged changes"),
            ["<leader>jt"] = jump_to_section("Untracked files"),
          },
        },
      })

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("NeogitJumpHints", { clear = true }),
        pattern = "NeogitStatus",
        callback = function(event)
          require("which-key").add({
            buffer = event.buf,
            { "<leader>j", group = "jump", icon = "󰁔" },
            { "<leader>ju", desc = "Jump to Unstaged Changes", icon = "" },
            { "<leader>js", desc = "Jump to Staged Changes", icon = "" },
            { "<leader>jt", desc = "Jump to Untracked Files", icon = "" },
          })
        end,
      })
    end,
    cmd = "Neogit",
    keys = {
      { "<leader>gn", "<cmd>Neogit<cr>", desc = "Show Neogit UI" },
    },
  },
}
