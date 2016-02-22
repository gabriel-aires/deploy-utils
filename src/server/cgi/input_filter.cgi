#!/bin/bash

# Filtra o input de formulários cgi
function input_filter() {

  set -f

  local params_group="$1"
  local params_value="$2"

  # Decodifica caracteres necessários,
  # Remove demais caracteres especiais,
  # Realiza substituições auxiliares

  params_value="$(echo "$params_value" | \
    sed -r 's|\+| |g' | \
    sed -r 's|%21|!|g' | \
    sed -r 's|%25|::percent::|g' | \
    sed -r 's|%2C|,|g' | \
    sed -r 's|%2F|/|g' | \
    sed -r 's|%3A|:|g' | \
    sed -r 's|%3D|=|g' | \
    sed -r 's|%40|@|g' | \
    sed -r 's|%..||g' | \
    sed -r 's|*||g' | \
    sed -r 's|::percent::|%|g' | \
    sed -r 's| +| |g' | \
    sed -r 's| $||g' \
  )"

  $params_group="$params_value"

  set +f

}
