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
touch "$config.tmp" || error=true
cp "$template" "$config.aux" || error=true

$error && log "ERRO" "Impossível escrever no diretório $(dirname $config)" && exit 1

#atualizar arrays associativos

processed=";"

while read line; do
    param="$(echo $line | sed -rn "s/^($regex[var)\[${regex[key]}\]]=.*$/\1/p")"
    test -z "$param" && continue
    echo "$processed" | grep -qF ";$param;" && continue
    replace_array=$(grep -Ex "$param\[$regex[key\]]=.*" "$config" | tr "\n" "\t")
    sed -i -r "s|^$param\[.*$|$replace_array|" "$config.aux" || error=true
    processed="$processed$param;"
done < "$config"

cat "$config.aux" | tr "\t" "\n" > "$config.tmp" || error=true
$error && log "ERRO" "Erro ao atualizar arrays associativos no template '$template'" && exit 1
rm -f "$config.aux"

#atualizar variáveis remanescentes

while read line; do
    param="$(echo $line | sed -rn "s/^([^=]+)=$/\1/p")"
    test -n "$param" || continue
    value=$(grep -Ex "$param=.*" "$config" | tail -n 1 | sed -rn "s/^$param=//p")
    sed -i -r "s|^($param=)$|\1$value|" "$config.tmp" || error=true
done < "$config.tmp"

if "$error"; then
    log "ERRO" "Impossível escrever no arquivo $config.tmp"
    rm -f "$config.tmp"
    exit 1
fi

mv "$config" "$config.bak"
mv "$config.tmp" "$config"
