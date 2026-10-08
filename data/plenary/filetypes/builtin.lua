local shebang_prefixes = { '/usr/bin/', '/bin/', '/usr/bin/env ', '/bin/env ' }
local shebang_fts = {
  fish = 'fish',
  perl = 'perl',
  python = 'python',
  python2 = 'python',
  python3 = 'python',
  bash = 'sh',
  sh = 'sh',
  zsh = 'zsh',
}

local shebang = {}
for _, prefix in ipairs(shebang_prefixes) do
  for k, v in pairs(shebang_fts) do
    shebang[prefix .. k] = v
  end
end

return {
  extension = {
    _coffee = 'coffee',
    astro = 'astro',
    cairo = 'cairo',
    cljd = 'clojure',
    coffee = 'coffee',
    cts = 'typescript',
    dart = 'dart',
    dtsi = 'dts',
    erb = 'eruby',
    ex = 'elixir',
    exs = 'elixir',
    fish = 'fish',
    fnl = 'fennel',
    gd = 'gdscript',
    gql = 'graphql',
    gradle = 'groovy',
    graphql = 'graphql',
    hbs = 'handlebars',
    hdbs = 'handlebars',
    hlsl = 'hlsl',
    jai = 'jai',
    janet = 'janet',
    jl = 'julia',
    jsx = 'javascriptreact',
    kt = 'kotlin',
    mts = 'typescript',
    nix = 'nix',
    plist = 'xml',
    purs = 'purescript',
    r = 'r',
    res = 'rescript',
    resi = 'rescript',
    rkt = 'racket',
    smithy = [[smithy]],
    sol = 'solidity',
    svelte = 'svelte',
    swift = 'swift',
    tres = 'gdresource',
    tscn = 'gdresource',
    tsx = 'typescriptreact',
    zig = 'zig',
    zon = 'zig',
  },
  file_name = {
    ['.babelrc'] = 'json',
    ['.clangd'] = 'yaml',
    ['.eslintrc'] = 'json',
    ['.firebaserc'] = 'json',
    ['.prettierrc'] = 'json',
    ['.stylelintrc'] = 'json',
    cakefile = 'coffee',
  },
  shebang = shebang
}
