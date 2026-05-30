-- Customize Treesitter

-- nvim 0.12 compat: vim.treesitter.Query:iter_matches returns a table of
-- nodes per capture, but nvim-treesitter master still treats captures as a
-- single TSNode. The `set-lang-from-info-string!` and `set-lang-from-mimetype!`
-- directives crash on markdown/HTML injections as a result. We re-register
-- both directives at runtime with `force = true`, so the plugin tree stays
-- clean and Lazy can update freely.
local function patch_directives()
  local ok, query = pcall(require, "vim.treesitter.query")
  if not ok then return end

  local opts = vim.fn.has("nvim-0.10") == 1 and { force = true, all = false } or true

  local html_script_type_languages = {
    importmap = "json",
    module = "javascript",
    ["application/ecmascript"] = "javascript",
    ["text/ecmascript"] = "javascript",
  }
  local aliases = { ex = "elixir", pl = "perl", sh = "bash", uxn = "uxntal", ts = "typescript" }

  local function first_node(n) if type(n) == "table" then return n[1] end return n end

  query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
    local node = first_node(match[pred[2]])
    if not node or not node.range then return end
    local alias = vim.treesitter.get_node_text(node, bufnr):lower()
    local fm = vim.filetype.match({ filename = "a." .. alias })
    metadata["injection.language"] = fm or aliases[alias] or alias
  end, opts)

  query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
    local node = first_node(match[pred[2]])
    if not node or not node.range then return end
    local value = vim.treesitter.get_node_text(node, bufnr)
    local configured = html_script_type_languages[value]
    if configured then
      metadata["injection.language"] = configured
    else
      local parts = vim.split(value, "/", {})
      metadata["injection.language"] = parts[#parts]
    end
  end, opts)
end

---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyLoad",
      desc = "Patch nvim-treesitter directives for nvim 0.12",
      callback = function(args)
        if args.data == "nvim-treesitter" then patch_directives() end
      end,
    })
  end,
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      -- add more arguments for adding more treesitter parsers
    },
  },
}
