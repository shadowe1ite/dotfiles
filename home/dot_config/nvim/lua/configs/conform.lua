local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    css = { "prettier" },
    html = { "prettier" },
    yaml = { "yamlfix" },
    python = { "black", "isort" },
    c = { "clang-format" },
    cpp = { "clang-format" },
    rust = { "rustfmt" },
    qml = { "/usr/lib/qt6/bin/qmlformat" },
  },

   format_on_save = {
     -- These options will be passed to conform.format()
     timeout_ms = 500,
     lsp_fallback = true,
   },
}

return options
