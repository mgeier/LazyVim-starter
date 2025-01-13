-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- globally disable auto-formatting
vim.g.autoformat = false

-- Set to `false` to globally disable all snacks animations
vim.g.snacks_animate = false

local opt = vim.opt

opt.cursorline = false
opt.ignorecase = false
opt.number = false
opt.relativenumber = false
opt.wrap = true
