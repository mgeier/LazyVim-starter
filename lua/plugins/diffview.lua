-- Preserve the cursor/scroll position in the revision window of a file history
-- view: both when opening it (start where :FileHistory was called from) and
-- when stepping through commits with <tab>/<s-tab>.
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

-- The plain (no diff) layout of :FileHistory is scoped to that one view instead
-- of the global config: the only place a file history view decides on a layout
-- is `self.parent.get_default_layout()` in FileHistoryPanel:update_entries, so
-- shadowing that method on the view instance is enough. update_entries is
-- scheduled from `post_open`, while the `view_opened` hook fires synchronously
-- right after it, so the override is in place before it is read.

local function realpath(path)
  if path == nil or path == "" then
    return nil
  end
  return vim.uv.fs_realpath(path) or path
end

-- Position captured by :FileHistory, consumed by the first revision that the
-- resulting history view opens.
local pending

local function on_view_opened(view)
  if view.class:name() ~= "FileHistoryView" then
    return
  end

  local saved, expect_path, plain
  if pending then
    saved, expect_path, plain = pending.view, pending.path, pending.plain
    pending = nil
  end
  local first = true

  if plain then
    local layout = require("diffview.config").name_to_layout("diff1_plain")
    view.get_default_layout = function()
      return layout
    end
  end

  view.emitter:on("file_open_pre", function(_, new_file)
    if first then
      -- Initial open: the main window still shows the null buffer, so there is
      -- nothing to capture -- keep the position seeded by :FileHistory, as long
      -- as it really is the file we were called from.
      first = false
      if expect_path and realpath(new_file and new_file.absolute_path) ~= expect_path then
        saved = nil
      end
      return
    end

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
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewLog" },
  opts = { hooks = { view_opened = on_view_opened } },
  init = function()
    -- :FileHistory (without diff), supports a range
    vim.api.nvim_create_user_command("FileHistory", function(opts)
      -- Make sure setup() (and thus the hook above) has run before the view is
      -- created, so that the hook can pick `pending` up.
      require("lazy").load({ plugins = { "diffview.nvim" } })
      pending = {
        path = realpath(vim.api.nvim_buf_get_name(0)),
        view = vim.fn.winsaveview(),
        plain = true,
      }
      if opts.range == 0 then
        vim.cmd("DiffviewFileHistory %")
      else
        vim.cmd(("%d,%dDiffviewFileHistory"):format(opts.line1, opts.line2))
      end
    end, { range = true, desc = "File/line history (plain)" })
  end,
}
