local M = {}

local server_job_id = nil

-- Run templ generate
M.generate = function()
  print("Generating Templ components...")
  vim.fn.jobstart({ "templ", "generate" }, {
    on_exit = function(_, code)
      if code == 0 then
        print("Templ generation complete")
        vim.cmd("checktime")
      else
        vim.api.nvim_err_writeln("Templ generation failed")
        vim.cmd("split | term templ generate")
      end
    end,
  })
end

M.build_css = function()
  print("Building Tailwind...")
  vim.fn.jobstart({
    "npx", "@tailwindcss/cli",
    "-i", "./static/css/input.css",
    "-o", "./static/css/output.css",
  }, {
    on_exit = function(_, code)
      if code == 0 then
        print("Tailwind build complete")
      else
        vim.api.nvim_err_writeln("Tailwind build failed")
      end
    end,
  })
end

-- Kill and run the Go server
M.run_server = function()
  if server_job_id ~= nil then
    vim.fn.jobstop(server_job_id)
    server_job_id = nil
    print("Old server stopped")
  end

  print("Starting new server...")
  vim.cmd("botright 5split | term go run ./cmd/server")
  server_job_id = vim.b.terminal_job_id
  local term_buf = vim.api.nvim_get_current_buf()

  vim.cmd("normal! G")
  vim.cmd("wincmd p")

  -- Close the terminal if the server started cleanly, keep it open on errors
  vim.defer_fn(function()
    local lines = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)
    local output = table.concat(lines, "\n")

    if string.find(output, "[Ee]rror") then
      print("Server error — terminal kept open")
    else
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == term_buf then
          vim.api.nvim_win_close(win, false)
          break
        end
      end
      print("Server started — terminal closed")
    end
  end, 2000)
end

-- Stop the server
M.stop_server = function()
  if server_job_id ~= nil then
    vim.fn.jobstop(server_job_id)
    server_job_id = nil
    print("Server stopped")
  else
    print("No server running")
  end
end

-- Refresh Firefox (macOS only)
-- Note: the /health poll in base.templ auto-reloads on server restart anyway.
M.firefox_refresh = function()
  local script = [[
    tell application "Firefox" to activate
    delay 0.1
    tell application "System Events" to keystroke "r" using command down
  ]]
  vim.fn.jobstart({ "osascript", "-e", script })
end

-- Refresh any Chromium-based browser (change browser name as needed)
M.browser_refresh = function()
  local browser = "Google Chrome" -- or "Arc", "Safari", etc.
  local cmd = string.format(
    "osascript -e 'tell application \"%s\" to tell the active tab of its first window to reload'",
    browser
  )
  vim.fn.jobstart(cmd)
end

-- Full dev cycle: templ → tailwind → server → browser refresh
M.dev = function()
  vim.fn.jobstart({ "templ", "generate" }, {
    on_exit = function(_, code)
      if code == 0 then
        M.build_css()
        M.run_server()
        vim.defer_fn(M.firefox_refresh, 800)
        print("GoTH Sync: Templ Generated | CSS Built | Server Restarted")
      else
        vim.api.nvim_err_writeln("GoTH: templ generate failed — aborting dev cycle")
      end
    end,
  })
end

-- Open and auto-tail clog.log in a bottom split
M.logs = function()
  vim.cmd("botright 8split | view clog.log")
  local log_buf = vim.api.nvim_get_current_buf()
  local log_win = nil

  vim.cmd("normal! G")
  vim.cmd("wincmd p")

  vim.defer_fn(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == log_buf then
        log_win = win
        break
      end
    end

    if log_win == nil then return end

    local timer = vim.loop.new_timer()
    timer:start(0, 2000, vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(log_buf) or not vim.api.nvim_win_is_valid(log_win) then
        timer:stop()
        timer:close()
        return
      end

      vim.cmd("checktime")

      -- Only auto-scroll if the cursor is already near the bottom
      local last_line = vim.api.nvim_buf_line_count(log_buf)
      local cursor = vim.api.nvim_win_get_cursor(log_win)
      if cursor[1] >= last_line - 1 then
        vim.api.nvim_win_set_cursor(log_win, { last_line, 0 })
      end
    end))
  end, 100)
end

-- Insert a SQL query block at cursor (pairs with dadbod)
M.insert_sql_block = function()
  local lines = {
    "-- sql",
    "SELECT * FROM  LIMIT 10;",
  }
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, lines)
  -- Place cursor on the SELECT line, before LIMIT so you can type the table name
  vim.api.nvim_win_set_cursor(0, { row + 2, 14 })
end

-- Open dadbod UI (requires vim-dadbod-ui to be installed)
M.open_db = function()
  vim.cmd("DBUIToggle")
end

-- Generate a QR code for the local server and open it in Safari.
-- Reads PORT from .env, falls back to 3060.
-- Requires: qrencode  (brew install qrencode)
M.qr = function()
  -- Read a key from .env
  local function read_env(key)
    local f = io.open(".env", "r")
    if not f then return nil end
    for line in f:lines() do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k == key then f:close(); return v end
    end
    f:close()
    return nil
  end

  local port = read_env("PORT") or "3060"

  -- Get the local Wi-Fi IP (macOS: ipconfig getifaddr en0)
  local handle = io.popen("ipconfig getifaddr en0 2>/dev/null")
  local ip = handle and handle:read("*l") or ""
  if handle then handle:close() end

  if not ip or ip == "" then
    vim.notify("GoTH QR: could not determine local IP (are you on Wi-Fi?)", vim.log.levels.ERROR)
    return
  end

  local url  = string.format("http://%s:%s", ip, port)
  local dest = "/tmp/goth_qr.png"

  vim.notify(string.format("GoTH QR: %s", url), vim.log.levels.INFO)

  vim.fn.jobstart({ "qrencode", "-o", dest, "-s", "10", url }, {
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("GoTH QR: qrencode failed — is it installed? (brew install qrencode)", vim.log.levels.ERROR)
        return
      end
      -- Open in Safari; non-blocking
      vim.fn.jobstart({ "open", "-a", "Safari", dest })
    end,
  })
end

-- Keymaps
M.setup = function()
  -- [T]empl [G]enerate
  vim.keymap.set("n", "<leader>tg", M.generate,         { desc = "GoTH: [T]empl [G]enerate" })
  -- [T]ailwind [C]ompile
  vim.keymap.set("n", "<leader>tc", M.build_css,         { desc = "GoTH: [T]ailwind [C]ompile" })
  -- [G]o [R]un / Restart server
  vim.keymap.set("n", "<leader>gr", M.run_server,        { desc = "GoTH: [G]o [R]un/Restart Server" })
  -- [G]o [S]top server
  vim.keymap.set("n", "<leader>gs", M.stop_server,       { desc = "GoTH: [G]o [S]top Server" })
  -- [G]oTH [D]evelop (full cycle)
  vim.keymap.set("n", "<leader>gd", M.dev,               { desc = "GoTH: [G]oTH [D]evelop" })
  -- [G]o [L]ogs
  vim.keymap.set("n", "<leader>gl", M.logs,              { desc = "GoTH: [G]o [L]ogs" })
  -- [S]QL [Q]uery block insert
  vim.keymap.set("n", "<leader>sq", M.insert_sql_block,  { desc = "GoTH: [S]QL [Q]uery block" })
  -- [D]atabase [U]I toggle
  vim.keymap.set("n", "<leader>du", M.open_db,           { desc = "GoTH: [D]atabase [U]I" })
  -- [Q]R code for mobile testing
  vim.keymap.set("n", "<leader>qr", M.qr,                { desc = "GoTH: [Q]R code (mobile test)" })
end

return M
