let pkgs = import <nixpkgs> { };
in pkgs.mkShell {
  packages = [ pkgs.odin pkgs.ols pkgs.emscripten ];
  shellHook = ''
    export EM_CACHE=/tmp
  '';
}

