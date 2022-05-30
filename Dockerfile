FROM nixpkgs/nix-flakes:latest
WORKDIR /ihp-elm
COPY ./ /ihp-elm
RUN nix build .#ihp-elm-prod
WORKDIR result/lib
CMD [ "../bin/RunProdServer" ]
