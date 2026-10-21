if vim.g.loaded_md_outline then
  return
end
vim.g.loaded_md_outline = true

vim.api.nvim_create_user_command("MdOutline", function()
  require("md-outline").toggle()
end, { desc = "Toggle the markdown outline" })

vim.api.nvim_create_user_command("MdOutlineOpen", function()
  require("md-outline").open()
end, { desc = "Open the markdown outline" })

vim.api.nvim_create_user_command("MdOutlineClose", function()
  require("md-outline").close()
end, { desc = "Close the markdown outline" })
