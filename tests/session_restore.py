"""Check restored Neo-tree sizing using installed plugins and isolated sessions."""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

INIT = r"""
vim.opt.rtp:prepend(vim.env.REPO)
for _, name in ipairs({ "plenary.nvim", "nui.nvim", "neo-tree.nvim", "persistence.nvim" }) do
  vim.opt.rtp:append(vim.env.PLUGINS .. "/" .. name)
end
vim.o.columns = 160
vim.o.lines = 48
vim.o.equalalways = true
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
require("persistence").setup({ dir = vim.env.CASE .. "/sessions/", branch = false })

local function tree_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
      return win
    end
  end
end

vim.schedule(function()
  local ok, err = xpcall(function()
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
      -- Normal exit exercises PersistenceSavePre and :mksession.
    else
      require("persistence").load()
      assert(vim.wait(3000, function()
        local win = tree_window()
        return win and vim.b[vim.api.nvim_win_get_buf(win)].neo_tree_source ~= nil
      end), "tree did not restore")
      vim.wait(100, function() return false end)
      local tree = tree_window()
      local expected = tonumber(vim.fn.readfile(vim.env.CASE .. "/size")[1])
      assert(dimension(tree) == expected, "initial restored size differs")
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


def run_case(repo, plugins, position):
    with tempfile.TemporaryDirectory(prefix="session-restore-") as directory:
        case = Path(directory)
        (case / "file.txt").write_text("session sizing fixture\n")
        init = case / "init.lua"
        init.write_text(INIT)
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
        for stage in ("save", "restore"):
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plugins", type=Path, default=Path.home() / ".local/share/nvim/lazy"
    )
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    for position in ("left", "right", "top", "bottom"):
        run_case(repo, args.plugins, position)
    print("PASS: restored Neo-tree keeps its saved dimensions after split/close")


if __name__ == "__main__":
    main()
