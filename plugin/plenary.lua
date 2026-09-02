vim.api.nvim_create_user_command("PlenaryBustedFile", function(args)
  require("plenary.test_harness").test_file(args.args)
end, { nargs = 1, complete = "file" })

vim.api.nvim_create_user_command("PlenaryBustedDirectory", function(args)
  require("plenary.test_harness").test_directory_command(args.args)
end, { nargs = "+", complete = "file" })

vim.keymap.set("n", "<Plug>PlenaryTestFile", function()
  require("plenary.test_harness").test_file(vim.fn.expand("%:p"))
end)
