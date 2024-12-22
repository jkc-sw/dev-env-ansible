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
            ansibleOverlayAllPyVersions
          ];
        };

        # Override ansible package in all python versions
        ansibleOverlayAllPyVersions = final: prev:
        let
          _overlay = pyfinal: pyprev: {
            ansible-core = pyprev.ansible-core.overridePythonAttrs (old: {
              dependencies = old.dependencies ++ [
                pyprev.debian
              ];
            });
          };
        in
        {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [ _overlay ];
        };

        pythonEnvWithPyDebian = pkgs.python312.withPackages (p: [p.debian]);

        packages = with pkgs; [
          bitwarden-cli
          jq
          pkgs.ansible
        ];

      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells.default = pkgs.mkShell {
          buildInputs = packages;
          # The following var is used in ansible-playbook like this `-e "ansible_python_interpreter=$EXPLICIT_PYTHON_PATH_FOR_ANSIBLE"`
          # I am using ansible_python_interpreter instead of ansible_playbook_python is because the remote host, aka localhost, needs
          #   the pydebian package and I want ansible to use a secific one.
          EXPLICIT_PYTHON_PATH_FOR_ANSIBLE = "${pythonEnvWithPyDebian}/bin/python3";
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


