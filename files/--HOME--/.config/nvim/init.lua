-- This file simply bootstraps the installation of Lazy.nvim and then calls other files for execution
-- This file doesn't necessarily need to be touched, BE CAUTIOUS editing this file and proceed at your own risk.

-- Force git clones spawned from nvim (lazy.nvim, mason, etc.) to use the legacy
-- "files" ref storage. With the global init.defaultRefFormat=reftable, git writes
-- .git/HEAD as a stub pointing at refs/heads/.invalid (the real ref lives in the
-- reftable). lazy.nvim reads .git/HEAD directly via file I/O, mis-detects the
-- branch as ".invalid", then injects an invalid fetch refspec into .git/config
-- via `git remote set-branches --add origin .invalid`, breaking every subsequent
-- git op on the plugin. gitdir-conditional includes don't help — they fire after
-- the new gitdir exists, but `git clone` decides the ref format before that.
vim.env.GIT_CONFIG_COUNT = "1"
vim.env.GIT_CONFIG_KEY_0 = "init.defaultRefFormat"
vim.env.GIT_CONFIG_VALUE_0 = "files"

local lazypath = vim.env.LAZY or vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
if not (vim.env.LAZY or (vim.uv or vim.loop).fs_stat(lazypath)) then
  -- stylua: ignore
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- validate that lazy is available
if not pcall(require, "lazy") then
  -- stylua: ignore
  vim.api.nvim_echo({ { ("Unable to load lazy from: %s\n"):format(lazypath), "ErrorMsg" }, { "Press any key to exit...", "MoreMsg" } }, true, {})
  vim.fn.getchar()
  vim.cmd.quit()
end

vim.o.modelines = 0

-- Autosave on InsertLeave
vim.api.nvim_create_augroup("autosave", { clear = true })
vim.api.nvim_create_autocmd(
  { "InsertLeave", "TextChanged", "FocusLost" },
  { group = "autosave", command = "silent! update" }
)

require "lazy_setup"
require "polish"
