#!/bin/bash

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

##### Execução somente como usuário root ######

if [ "$(id -u)" -ne "0" ]; then
    log "ERRO" "Requer usuário root."
    exit 1
fi

#### validação ####

test "$#" -ne 2 && log "ERRO" "O script requer 2 argumentos" && exit 1
test ! -f "$1" && log "ERRO" "O primeiro argumento deve ser um arquivo de configuração" && exit 1
test ! -f "$2" && log "ERRO" "O segundo argumento deve ser um template de configuração" && exit 1
echo "$1" | grep -Exv ".*\.conf$" &> /dev/null && log "ERRO" "O primeiro arquivo deve possuir extensão .conf" && exit 1
echo "$2" | grep -Exv ".*\.template$" &> /dev/null && log "ERRO" "O segundo arquivo deve possuir extensão .template"  && exit 1

config="$1"
template="$2"
error=false

touch "$config" || error=true
cp "$template" "$config.tmp" || error=true

if "$error"; then
    log "ERRO" "Impossível escrever no diretório $(dirname $config)"
    exit 1
fi

while read line; do
    key="$(echo $line | sed -rn "s/^([^=]+)=$/\1/p")"
    test -n "$key" || continue
    value=$(grep -Ex "$key=.*" "$config" | tail -n 1 | sed -rn "s/^$key=//p")
    sed -i -r "s|^($key=)$|\1$value|" "$config.tmp" || error=true
done < "$config.tmp"

if "$error"; then
    log "ERRO" "Impossível escrever no arquivo $config.tmp"
    rm -f "$config.tmp"
    exit 1
fi

mv "$config" "$config.bak"
mv "$config.tmp" "$config"
