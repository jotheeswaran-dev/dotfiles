-- Override the astrocommunity markdown-preview-nvim spec's build step.
-- Upstream runs `vim.fn["mkdp#util#install"]()`, but at lazy.nvim build time the
-- plugin's autoload/ isn't on runtimepath yet, so it throws E117. Prepend the
-- plugin dir first so the autoload function resolves, then download the
-- prebuilt preview server (no node build needed).
---@type LazySpec
return {
  "iamcco/markdown-preview.nvim",
  build = function(plugin)
    vim.opt.runtimepath:prepend(plugin.dir)
    vim.fn["mkdp#util#install"]()
  end,
  init = function()
    -- Per-open browser picker: every :MarkdownPreview asks which browser to use.
    -- Add lines here to expand the menu (app name = what `open -a` expects).
    vim.cmd([[
      function! MkdpChooseBrowser(url) abort
        let l:choice = confirm('Open Markdown preview in:', "&Arc\n&Brave\n&Default browser", 1)
        if l:choice == 1
          call jobstart(['open', '-a', 'Arc', a:url])
        elseif l:choice == 2
          call jobstart(['open', '-a', 'Brave Browser', a:url])
        elseif l:choice == 3
          call jobstart(['open', a:url])
        endif
      endfunction
    ]])
    vim.g.mkdp_browserfunc = "MkdpChooseBrowser"
  end,
}
