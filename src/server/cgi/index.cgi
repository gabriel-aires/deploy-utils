#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/init.sh || exit 1

### HTML
echo 'Content-type: text/html'
echo ''
echo '<html>'
echo '  <head>'
echo '      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">'
echo "  <title>$html_title</title"
echo '  </head>'
echo '  <body>'
echo "      <h1>$html_header</h1>"

### QUERY HISTORY
if [ -f  $history_dir/$history_csv_file ]; then
    $install_dir/cgi/html_table.cgi $history_dir/$history_csv_file
else
    echo '  <p>Histórico de deploy inexistente</p>'
fi

echo '  </body>'
echo '</html>'
