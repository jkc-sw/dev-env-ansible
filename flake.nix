{
  description = "Provide ansible for my dependencies";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          system = "${system}";
          overlays = [
            ansibleOverlay
          ];
        };

        ansibleOverlay = final: prev: {
          python312 = prev.python312.override {
            packageOverrides = pyfinal: pyprev: {
              ansible-core = pyprev.ansible-core.overrideAttrs (old: {
                propagatedBuildInputs = old.propagatedBuildInputs ++ [
                  pyprev.debian
                ];
              });
            };
          };
        };

        pythonEnvWithAnsible = pkgs.python312.withPackages (p: [p.ansible p.ansible-core p.debian]);

        packages = with pkgs; [
          bitwarden-cli
          jq
          pythonEnvWithAnsible
        ];

      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells.default = pkgs.mkShell {
          buildInputs = packages;
          # The following var is used in ansible-playbook like this `-e "ansible_playbook_python=$EXPLICIT_PYTHON_PATH_FOR_ANSIBLE"`
          EXPLICIT_PYTHON_PATH_FOR_ANSIBLE = "${pythonEnvWithAnsible}/bin/python3";
          shellHook = ''
            export IN_NIX_RR_SHELL=1
            if [[ -z "$DISPLAY" ]]; then
              export DISPLAY=:1
            fi
            if [[ -e /usr/lib/locale/locale-archive ]]; then
                export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
            else
                echo 'WARN: Unable to export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive' >&2
            fi
            if [[ -e /etc/ssl/certs/ca-certificates.crt ]]; then
                export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
            else
                echo 'WARN: Unable to export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt' >&2
            fi
          '';
        };
      }
    );
}

/*
  SOURCE_THESE_VIMS_START
  nnoremap <leader>no <cmd> silent call execute(escape("!tmux send-keys -t :.+1 './shell.sh' Enter", '#'))<cr>
  nnoremap <leader>ne <cmd> silent call execute(escape("!tmux send-keys -t :.+1 'export NIXPKGS_ALLOW_UNFREE=1 ; nix develop --impure . -L' Enter", '#'))<cr>
  nnoremap <leader>nu <cmd> silent call execute(escape("!tmux send-keys -t :.+1 'git push' Enter", '#'))<cr>
  echom 'Sourced'
  SOURCE_THESE_VIMS_END
*/

# vim:et ts=2 sts=2 sw=2


