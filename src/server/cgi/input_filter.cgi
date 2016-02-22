#!/bin/bash

# Filtra o input de formulários cgi
function input_filter() {

  set -euf

  local params_group="$1"
  local params_value="$2"

  $params_group="$(echo "$params_value" | \

    # Decodifica caracteres necessários
    sed -r 's|\+| |g' | \
    sed -r 's|%21|!|g' | \
    sed -r 's|%25|::percent::|g' | \
    sed -r 's|%2C|,|g' | \
    sed -r 's|%2F|/|g' | \
    sed -r 's|%3A|:|g' | \
    sed -r 's|%3D|=|g' | \
    sed -r 's|%40|@|g' | \

    # Remove demais caracteres especiais
    sed -r 's|%..||g' | \
    sed -r 's|*||g' | \

    # Substituições auxiliares
    sed -r 's|::percent::|%|g' \
    sed -r 's| +| |g' \
    sed -r 's| $||g' \
  )"

  set +euf

}
