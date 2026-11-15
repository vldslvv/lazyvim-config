"""Check restored pane sizing and status-line placement with installed plugins."""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

INIT = r"""
vim.opt.rtp:prepend(vim.env.REPO)
for _, name in ipairs({ "plenary.nvim", "nui.nvim", "neo-tree.nvim", "persistence.nvim", "noice.nvim" }) do
  vim.opt.rtp:append(vim.env.PLUGINS .. "/" .. name)
end
vim.o.columns = 160
vim.o.lines = 48
vim.o.equalalways = true
vim.o.laststatus = 3
require("noice").setup({
  lsp = { hover = { enabled = false }, signature = { enabled = false } },
})
local vertical = vim.env.POSITION == "left" or vim.env.POSITION == "right"
local dimension = vertical and vim.api.nvim_win_get_width or vim.api.nvim_win_get_height
local function focus_file()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == vim.env.CASE .. "/file.txt" then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
  error("file window missing")
end
local opts = require("plugins.neo-tree")[1].opts(nil, {})
opts.enable_git_status = false
opts.enable_diagnostics = false
opts.filesystem.use_libuv_file_watcher = false
require("neo-tree").setup(opts)
require("local_plugins.session_restore").setup()

local function tree_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
      return win
    end
  end
end

vim.schedule(function()
  local ok, err = xpcall(function()
    assert(vim.wait(3000, function() return vim.o.cmdheight == 0 end), "Noice did not hide the command line")
    -- Persistence loads on the first file, after Noice. On exit, Noice detaches
    -- first, reserving a command-line row before the session sizes are captured.
    require("persistence").setup({ dir = vim.env.CASE .. "/sessions/", branch = false })
    if vim.env.STAGE == "save" then
      vim.cmd.edit(vim.env.CASE .. "/file.txt")
      require("neo-tree.command").execute({ position = vim.env.POSITION, dir = vim.env.CASE })
      assert(vim.wait(3000, function() return tree_window() ~= nil end), "tree did not open")
      if vertical then
        vim.api.nvim_win_set_width(tree_window(), 37)
      else
        vim.api.nvim_win_set_height(tree_window(), 11)
      end
      focus_file()
      vim.fn.writefile({ tostring(dimension(tree_window())) }, vim.env.CASE .. "/size")
      vim.cmd.tabnew(vim.env.CASE .. "/file.txt")
      vim.cmd.tabprevious()
      -- Normal exit exercises PersistenceSavePre and :mksession.
    else
      require("persistence").load()
      assert(vim.wait(3000, function()
        local win = tree_window()
        return win and vim.b[vim.api.nvim_win_get_buf(win)].neo_tree_source ~= nil
      end), "tree did not restore")
      vim.wait(100, function() return false end)
      local selected = vim.api.nvim_get_current_tabpage()
      assert(#vim.api.nvim_list_tabpages() == 2, "session did not restore both tabs")
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        vim.api.nvim_set_current_tabpage(tab)
        assert(vim.o.cmdheight == 0, "restoring pane sizes moved the status line above a blank command-line row")
      end
      vim.api.nvim_set_current_tabpage(selected)
      local tree = tree_window()
      local expected = tonumber(vim.fn.readfile(vim.env.CASE .. "/size")[1])
      assert(dimension(tree) == expected, string.format(
        "%s initial restored size differs: expected=%d, actual=%d", vim.env.POSITION, expected, dimension(tree)
      ))
      focus_file()
      if vertical then
        vim.cmd.vsplit()
      else
        vim.cmd.split()
      end
      vim.cmd.close()
      vim.wait(100, function() return false end)
      local actual = dimension(tree)
      print(string.format("%s Neo-tree size: saved=%d, after split/close=%d", vim.env.POSITION, expected, actual))
      assert(actual == expected, "restored Neo-tree expanded after closing the split")
      require("persistence").stop()
    end
  end, debug.traceback)
  if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
  end
  vim.cmd("qa!")
end)
"""

UTILITY_INIT = r"""
vim.opt.rtp:prepend(vim.env.REPO)
for _, name in ipairs({ "lazy.nvim", "LazyVim", "plenary.nvim", "nui.nvim", "neo-tree.nvim", "neogit", "snacks.nvim" }) do
  vim.opt.rtp:append(vim.env.PLUGINS .. "/" .. name)
end
vim.o.columns = 160
vim.o.lines = 48
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }
local persistence
for _, spec in ipairs(require("lazyvim.plugins.util")) do
  if spec[1] == "folke/persistence.nvim" then
    persistence = spec
    persistence.dir = vim.env.PLUGINS .. "/persistence.nvim"
    persistence.opts = { dir = vim.env.CASE .. "/sessions/", branch = false }
  end
end
require("lazy").setup({
  spec = { persistence, require("plugins.persistence")[1] },
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  performance = { rtp = { reset = false } },
  lockfile = vim.env.CASE .. "/lazy-lock.json",
})
local function utility_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == vim.env.POSITION then
      return win
    end
  end
end
vim.schedule(function()
  local ok, err = xpcall(function()
    if vim.env.STAGE == "seed" then
      vim.cmd.edit(vim.env.CASE .. "/file.txt")
    elseif vim.env.STAGE == "idle" then
      -- An untouched startup screen must keep the previous session.
    elseif vim.env.STAGE == "loaded-idle" then
      -- Loading the session picker and cancelling must keep it too.
      require("persistence")
    elseif vim.env.STAGE == "save" then
      require("snacks").setup({ dashboard = { enabled = false } })
      require("snacks").dashboard.open({ buf = 0, win = 0, sections = { { text = "Session fixture" } } })
      if vim.env.POSITION == "neo-tree" then
        local opts = require("plugins.neo-tree")[1].opts(nil, {})
        opts.enable_git_status = false
        opts.enable_diagnostics = false
        opts.filesystem.use_libuv_file_watcher = false
        require("neo-tree").setup(opts)
        require("neo-tree.command").execute({ position = "left", dir = vim.env.CASE })
      else
        require("neogit").setup({ integrations = { diffview = false, telescope = false } })
        require("neogit").open({ kind = "replace", cwd = vim.env.CASE })
      end
      assert(vim.wait(3000, function() return utility_window() ~= nil end), "utility pane did not open")
      if vim.env.POSITION == "neo-tree" then
        vim.api.nvim_win_set_width(utility_window(), 37)
      end
      vim.api.nvim_set_current_win(utility_window())
    else
      require("persistence").load()
      assert(vim.wait(3000, function()
        local win = utility_window()
        return win and (vim.env.POSITION ~= "neo-tree" or vim.b[vim.api.nvim_win_get_buf(win)].neo_tree_source ~= nil)
      end), "utility-only session restored the older file session instead of the utility pane")
      vim.wait(100, function() return false end)
      assert(vim.api.nvim_get_current_win() == utility_window(), "restored utility pane lost focus")
      if vim.env.POSITION == "neo-tree" then
        assert(vim.api.nvim_win_get_width(utility_window()) == 37, "restored tree lost its saved width")
        local state = require("neo-tree.sources.manager").get_state_for_window(utility_window())
        assert(state.path == vim.env.CASE, "restored tree lost its root")
      end
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) ~= vim.env.CASE .. "/file.txt",
          "restore reopened a stale file from the previous session")
      end
      require("persistence").stop()
    end
  end, debug.traceback)
  if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
  end
  vim.cmd("qa!")
end)
"""


def run_case(repo, plugins, position, init_source=INIT, stages=("save", "restore")):
    with tempfile.TemporaryDirectory(prefix="session-restore-") as directory:
        case = Path(directory)
        (case / "file.txt").write_text("session sizing fixture\n")
        init = case / "init.lua"
        init.write_text(init_source)
        if position == "NeogitStatus":
            subprocess.run(["git", "init", "-q", str(case)], check=True)
        env = dict(
            os.environ,
            REPO=str(repo),
            PLUGINS=str(plugins.resolve()),
            CASE=str(case),
            POSITION=position,
        )
        for kind in ("CONFIG", "DATA", "STATE", "CACHE"):
            env[f"XDG_{kind}_HOME"] = str(case / kind.lower())
            (case / kind.lower() / "nvim").mkdir(parents=True)
        env["NVIM_LOG_FILE"] = str(case / "nvim.log")
        for stage in stages:
            previous = {
                p.name: p.read_bytes() for p in (case / "sessions").glob("*.vim")
            }
            result = subprocess.run(
                ["nvim", "--headless", "-i", "NONE", "-u", str(init)],
                check=False,
                cwd=case,
                env=dict(env, STAGE=stage),
                capture_output=True,
                text=True,
                timeout=15,
            )
            print(result.stdout + result.stderr, end="")
            if result.returncode:
                raise SystemExit(result.returncode)
            if stage == "seed":
                assert list((case / "sessions").glob("*.vim")), (
                    "seed session was not saved"
                )
            if stage in ("idle", "loaded-idle"):
                current = {
                    p.name: p.read_bytes() for p in (case / "sessions").glob("*.vim")
                }
                assert current == previous, (
                    "unused editor overwrote the previous session"
                )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plugins", type=Path, default=Path.home() / ".local/share/nvim/lazy"
    )
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    for position in ("left", "right", "top", "bottom"):
        run_case(repo, args.plugins, position)
    for pane in ("neo-tree", "NeogitStatus"):
        run_case(
            repo,
            args.plugins,
            pane,
            init_source=UTILITY_INIT,
            stages=("seed", "idle", "loaded-idle", "save", "restore"),
        )
    print(
        "PASS: pane sizing, status-line placement, utility-only sessions, and unused-editor preservation"
    )


if __name__ == "__main__":
    main()
