local M = {}

function M.setup()
  require("dap") -- Define DAP's signs before restoring any breakpoints.
  local breakpoints = require("dap.breakpoints")
  local directory = vim.fn.stdpath("state") .. "/dap-breakpoints"
  local restored = {}
  local group = vim.api.nvim_create_augroup("PersistentDapBreakpoints", { clear = true })

  local function filename(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and vim.bo[buf].buftype == "" then
      return name
    end
  end

  local function location(name)
    return directory .. "/" .. vim.fn.sha256(name) .. ".json"
  end

  local function warn(message)
    vim.notify("Breakpoint persistence: " .. message, vim.log.levels.WARN)
  end

  local function restore(buf)
    local name = filename(buf)
    if not name or restored[buf] then
      return
    end
    restored[buf] = name
    local path = location(name)
    if vim.fn.filereadable(path) == 0 then
      return
    end
    local ok, data = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    end)
    if
      not ok
      or type(data) ~= "table"
      or data.version ~= 1
      or data.file ~= name
      or type(data.breakpoints) ~= "table"
    then
      warn("could not read " .. path)
      return
    end
    -- Do not replace breakpoints already set before this module was loaded.
    if #(breakpoints.get(buf)[buf] or {}) > 0 then
      return
    end
    for _, bp in ipairs(data.breakpoints) do
      if
        type(bp) == "table"
        and type(bp.line) == "number"
        and bp.line % 1 == 0
        and bp.line >= 1
        and bp.line <= vim.api.nvim_buf_line_count(buf)
        and (bp.condition == nil or type(bp.condition) == "string")
        and (bp.hitCondition == nil or type(bp.hitCondition) == "string")
        and (bp.logMessage == nil or type(bp.logMessage) == "string")
      then
        breakpoints.set({
          condition = bp.condition,
          hit_condition = bp.hitCondition,
          log_message = bp.logMessage,
        }, buf, bp.line)
      end
    end
  end

  local function save(buf)
    local name = filename(buf)
    if not name or restored[buf] ~= name then
      return
    end
    local entries = {}
    for _, bp in ipairs(breakpoints.get(buf)[buf] or {}) do
      entries[#entries + 1] = {
        line = bp.line,
        condition = bp.condition,
        hitCondition = bp.hitCondition,
        logMessage = bp.logMessage,
      }
    end
    local path = location(name)
    if #entries == 0 then
      vim.fn.delete(path)
      return
    end
    -- Rename a complete file so an interrupted write cannot truncate the old one.
    local temporary = path .. "." .. vim.fn.getpid() .. ".tmp"
    local ok, err = pcall(function()
      vim.fn.mkdir(directory, "p")
      local data = vim.json.encode({ version = 1, file = name, breakpoints = entries })
      assert(vim.fn.writefile({ data }, temporary) == 0, "write failed")
      assert(vim.fn.rename(temporary, path) == 0, "rename failed")
    end)
    if not ok then
      vim.fn.delete(temporary)
      warn("could not save " .. name .. ": " .. tostring(err))
    end
  end

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    callback = function(event)
      restore(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufUnload" }, {
    group = group,
    callback = function(event)
      save(event.buf)
      if event.event == "BufUnload" then
        restored[event.buf] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          save(buf)
        end
      end
    end,
  })
  -- Restore before the key that triggered lazy loading can toggle a breakpoint.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      restore(buf)
    end
  end
end

return M
