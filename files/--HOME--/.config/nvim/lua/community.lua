-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  { import = "astrocommunity.pack.lua" },
  { import = "astrocommunity.colorscheme.catppuccin" },
  { import = "astrocommunity.recipes.telescope-lsp-mappings" },
  { import = "astrocommunity.pack.python" },
  { import = "astrocommunity.pack.rust" },
  { import = "astrocommunity.motion.tabout-nvim" },
  { import = "astrocommunity.scrolling.mini-animate" },
  { import = "astrocommunity.markdown-and-latex.render-markdown-nvim" },
  { import = "astrocommunity.editing-support.vim-visual-multi" },
  { import = "astrocommunity.pack.python-ruff" },
  { import = "astrocommunity.pack.sql" },
  { import = "astrocommunity.pack.typescript" },
  { import = "astrocommunity.pack.tailwindcss" },
  { import = "astrocommunity.colorscheme.github-nvim-theme" },
  { import = "astrocommunity.motion.nvim-surround" },
  { import = "astrocommunity.terminal-integration.vim-tmux-navigator"},
  { import = "astrocommunity.file-explorer.oil-nvim"},
}
