-- Preserve the cursor/scroll position in the revision window when stepping
-- through commits in a file history view.
--
-- Diffview resets it: on every new file entry it emits `file_open_new`, and its
-- own listener for that event does `set_cursor(main_win, 1, 0)` (see
-- scene/views/file_history/listeners.lua). That listener runs *after* both
-- BufWinEnter and the `diff_buf_win_enter` hook, which is why generic buffer
-- autocmds get overwritten.
--
-- So: save the view on `file_open_pre` (the window still shows the old
-- revision at that point), and restore from `file_open_post` via vim.schedule
-- -- everything after `file_open_post` in FileHistoryView:_set_file is
-- synchronous, so the scheduled callback lands after the reset and after
-- Layout:sync_scroll.
local function keep_position(view)
  if view.class:name() ~= "FileHistoryView" then
    return
  end

  local saved

  view.emitter:on("file_open_pre", function(_, new_file)
    saved = nil
    local win = view.cur_layout and view.cur_layout:get_main_win()
    if not (win and win:is_valid() and win.file) then
      return
    end
    -- Only for successive revisions of the same path (multi-file history can
    -- switch files between entries, where a position makes no sense).
    if new_file and new_file.path ~= win.file.path then
      return
    end
    saved = vim.api.nvim_win_call(win.id, vim.fn.winsaveview)
  end)

  view.emitter:on("file_open_post", function()
    local v = saved
    if not v then
      return
    end
    vim.schedule(function()
      local win = view.cur_layout and view.cur_layout:get_main_win()
      if not (win and win:is_valid()) then
        return
      end
      local last = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win.id))
      vim.api.nvim_win_call(win.id, function()
        vim.fn.winrestview(vim.tbl_extend("force", v, {
          lnum = math.min(v.lnum, last),
          topline = math.min(v.topline, last),
        }))
      end)
    end)
  end)
end

return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewFileHistory" },
  opts = { hooks = { view_opened = keep_position } },
  init = function()
    -- :FileHistory (without diff), supports a range
    vim.api.nvim_create_user_command("FileHistory", function(opts)
      -- Make sure setup() (and thus the hook above) has run before we poke at
      -- the config, otherwise setup() would overwrite the layout below.
      require("lazy").load({ plugins = { "diffview.nvim" } })
      require("diffview.config").get_config().view.file_history.layout = "diff1_plain"
      if opts.range == 0 then
        vim.cmd("DiffviewFileHistory %")
      else
        vim.cmd(("%d,%dDiffviewFileHistory"):format(opts.line1, opts.line2))
      end
    end, { range = true, desc = "File/line history (plain)" })
  end,
}
