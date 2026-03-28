return {
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      { "tpope/vim-dadbod",                lazy = true },
      { "kristijanhusak/vim-dadbod-completion",
        ft = { "sql", "mysql", "plsql" }, lazy = true },
    },
    cmd = {
      "DBUI",
      "DBUIToggle",
      "DBUIAddConnection",
      "DBUIFindBuffer",
    },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_help      = 0
      vim.g.db_ui_win_width      = 35
      vim.g.db_ui_default_query_results_location = "horizontal"

      -- Read DB_UI_DEV from the project's .env so the connection string
      -- stays out of version control and matches whatever is in .env.
      local function read_env(key)
        local f = io.open(".env", "r")
        if not f then return nil end
        for line in f:lines() do
          local k, v = line:match("^%s*([%w_]+)%s*=%s*(.+)%s*$")
          if k == key then
            f:close()
            return v
          end
        end
        f:close()
        return nil
      end

      local db_url = read_env("DB_UI_DEV")
      if db_url then
        -- Sets a project-local g:dbs entry so dadbod picks it up automatically.
        vim.g.dbs = { { name = "dev", url = db_url } }
      end
    end,
  },
}
