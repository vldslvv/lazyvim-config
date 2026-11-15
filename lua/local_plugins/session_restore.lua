local M = {}

local function windows(tab)
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(tab))
end

local function snapshot()
  local state = { version = 1, active_tab = vim.fn.tabpagenr(), tabs = {}, entries = {} }
  for tab_index, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local active = vim.api.nvim_tabpage_get_win(tab)
    local tab_state = { resize = vim.api.nvim_win_call(active, vim.fn.winrestcmd) }
    for win_index, win in ipairs(windows(tab)) do
      if win == active then
        tab_state.active_win = win_index
      end
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local entry = { tab = tab_index, win = win_index, kind = ft, name = vim.api.nvim_buf_get_name(buf) }
      if ft == "NeogitStatus" then
        entry.cwd = vim.api.nvim_win_call(win, vim.fn.getcwd)
        state.entries[#state.entries + 1] = entry
      elseif ft == "neo-tree" then
        local tree = vim.api.nvim_win_call(win, function()
          return require("neo-tree.sources.manager").get_state_for_window(win)
        end)
        if tree then
          entry.source = tree.name
          entry.position = tree.current_position
          entry.cwd = tree.path
          state.entries[#state.entries + 1] = entry
        end
      end
    end
    state.tabs[tab_index] = tab_state
  end
  return state
end

local function saved_window(tabs, entry)
  local tab = tabs[entry.tab]
  return tab and vim.api.nvim_tabpage_is_valid(tab) and windows(tab)[entry.win] or nil
end

local function empty_window(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_buf_get_name(buf) == ""
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function clear_placeholder_names(state)
  local tabs = vim.api.nvim_list_tabpages()
  for _, entry in ipairs(state.entries) do
    local win = saved_window(tabs, entry)
    if win then
      local buf = vim.api.nvim_win_get_buf(win)
      if
        entry.name == vim.api.nvim_buf_get_name(buf)
        and (vim.bo[buf].buftype == "" or vim.bo[buf].buftype == "nofile")
        and vim.b[buf].neo_tree_source == nil
        and vim.api.nvim_buf_line_count(buf) == 1
        and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
        and not (vim.uv or vim.loop).fs_stat(entry.name)
      then
        -- :mksession gives blank nofile panes their old names and, with
        -- localoptions, their old buffer type. Normalize both so restore can
        -- reuse the slot. Never reset a live Neo-tree buffer on a warm load.
        -- Neogit also deletes its old names on SessionLoadPost, closing tabs.
        vim.api.nvim_buf_set_name(buf, "")
        vim.bo[buf].buftype = ""
        vim.bo[buf].filetype = ""
        -- EditorConfig can mark an empty placeholder modified by setting its
        -- encoding on BufFilePost. There is no file or text here to preserve.
        vim.bo[buf].modified = false
        vim.bo[buf].buflisted = false
      end
    end
  end
end

local function warn_unrestored_trees()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(windows(tab)) do
      local buf = vim.api.nvim_win_get_buf(win)
      local name = vim.api.nvim_buf_get_name(buf)
      if
        vim.fs.basename(name):match("^neo%-tree [%w_]+ %[%d+%]$")
        and vim.b[buf].neo_tree_source == nil
        and not (vim.uv or vim.loop).fs_stat(name)
      then
        vim.notify(
          "Session pane restore: could not restore Neo-tree (missing or incompatible pane metadata). "
            .. "Reopen Neo-tree and save a new session.",
          vim.log.levels.WARN
        )
        return
      end
    end
  end
end

local function restore_neogit(entry, win, buffers)
  local buf = buffers[entry.cwd]
  if not buf then
    vim.api.nvim_set_current_win(win)
    require("neogit").open({ kind = "replace", cwd = entry.cwd, no_expand = true })
    buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].filetype ~= "NeogitStatus" then
      return
    end
    buffers[entry.cwd] = buf
  else
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_call(win, function()
      vim.cmd.lcd(vim.fn.fnameescape(entry.cwd))
    end)
  end
end

local function restore_tree(entry, win, done)
  require("neo-tree").ensure_config()
  local manager = require("neo-tree.sources.manager")
  vim.api.nvim_set_current_win(win)
  local state = manager.get_state(entry.source, nil, entry.position == "current" and win or nil)
  state.current_position = entry.position
  if entry.position ~= "current" then
    -- Let Neo-tree adopt the saved split instead of creating another sidebar.
    require("neo-tree.ui.windows").get_location(entry.position).winid = win
    -- Adoption skips NuiSplit's window setup. Restore its sizing constraints
    -- so later splits and closes do not equalize the sidebar with file panes.
    vim.wo[win].winfixwidth = true
    vim.wo[win].winfixheight = true
  end
  require("neo-tree.ui.renderer").acquire_window(state)
  -- Navigate in series: filesystem navigation is debounced across all tabs.
  manager.navigate(state, entry.cwd, nil, done, false)
end

local function restore(state)
  local tabs = vim.api.nvim_list_tabpages()
  local buffers = {}
  local targets = {}
  local selected = {}
  for index, tab_state in ipairs(state.tabs) do
    selected[index] = saved_window(tabs, { tab = index, win = tab_state.active_win })
  end
  for _, entry in ipairs(state.entries) do
    local win = saved_window(tabs, entry)
    if win and empty_window(win) then
      targets[#targets + 1] = { entry = entry, win = win }
    end
  end

  local function finish()
    for index, tab_state in ipairs(state.tabs) do
      local win = selected[index]
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        -- Neo-tree's open handler equalizes panes; put the saved sizes back.
        vim.cmd(tab_state.resize)
      end
    end
    local win = selected[state.active_tab]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
    warn_unrestored_trees()
  end

  local function next_entry(index)
    local target = targets[index]
    if not target then
      finish()
      return
    end
    local entry, win = target.entry, target.win
    local ok, err = pcall(function()
      if entry.kind == "NeogitStatus" and vim.fn.isdirectory(entry.cwd) == 1 then
        restore_neogit(entry, win, buffers)
      elseif entry.kind == "neo-tree" then
        restore_tree(entry, win, function()
          next_entry(index + 1)
        end)
        return
      end
    end)
    if not ok then
      vim.notify("Session pane restore: " .. tostring(err), vim.log.levels.WARN)
    end
    if not ok or entry.kind ~= "neo-tree" then
      next_entry(index + 1)
    end
  end
  next_entry(1)
end

function M.setup()
  -- Keep slots for nofile panes. Their contents are recreated by the plugins.
  vim.opt.sessionoptions:append({ "blank", "globals" })
  local group = vim.api.nvim_create_augroup("WorkspaceSessionRestore", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "PersistenceSavePre",
    callback = function()
      -- A string global is written by :mksession itself, so skipped/failed saves
      -- cannot overwrite metadata belonging to the previous session file.
      vim.g.WorkspaceSessionState = vim.json.encode(snapshot())
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "PersistenceLoadPre",
    callback = function()
      vim.g.WorkspaceSessionState = nil
      -- Existing tree buffers can be reused by :source before our placeholders
      -- are restored, leaving duplicate trees in saved file panes. Dispose the
      -- old layout first, including hidden trees and trees in other tabs.
      local manager = package.loaded["neo-tree.sources.manager"]
      if manager then
        manager.dispose()
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "PersistenceLoadPost",
    callback = function()
      local ok, state = pcall(vim.json.decode, vim.g.WorkspaceSessionState or "")
      if
        not ok
        or type(state) ~= "table"
        or state.version ~= 1
        or type(state.tabs) ~= "table"
        or type(state.entries) ~= "table"
      then
        vim.notify(
          "Session pane restore: missing or incompatible pane metadata. Reopen utility panes and save a new session.",
          vim.log.levels.WARN
        )
        return
      end
      clear_placeholder_names(state)
      -- Run after Neogit's SessionLoadPost cleanup of stale status buffers.
      vim.schedule(function()
        restore(state)
      end)
    end,
  })
end

return M
