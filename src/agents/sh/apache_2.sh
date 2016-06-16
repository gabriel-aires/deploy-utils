#!/bin/bash

function copy_log () {

    log "INFO" "Buscando logs do servidor apache..."

    regex_serverroot_directive="^[[:blank:]]*ServerRoot [^[:blank:]]+$"
    regex_include_directive="^[[:blank:]]*Include(Optional)? [^;\&\$\` ]+\.conf$"
    regex_log_directive="^[[:blank:]]*(Custom|Error|Global|Script|Transfer)Log [^;\&\$\` ]+( .+)*$"

    test ! -f "$apache_configuration" && log "ERRO" "Arquivo de configuração do apache não identificado. Abortando..." && return 1
    serverroot="$(grep -Ex "$regex_serverroot_directive" "$apache_configuration" | tail -n 1 | sed -r "s|^[[:blank:]]*||" | cut -d ' ' -f2)"
    test ! -d "$serverroot" && log "ERRO" "Diretório raiz do apache não identificado. Abortando..." && return 1

    grep -Ex "$regex_include_directive" "$apache_configuration" | sed -r "s|^[[:blank:]]*||" | cut -d ' ' -f2 > $tmp_dir/apache_includes.list
    touch $tmp_dir/apache_logs.list

    cat $tmp_dir/apache_includes.list | while read apache_includes; do
        grep -Exh "$regex_log_directive" $apache_includes | sed -r "s|^[[:blank:]]*||" | cut -d ' ' -f2 >> $tmp_dir/apache_logs.list
    done

    sed -r "s|\'||g" $tmp_dir/apache_logs.list | sed -r 's|\"||g' | sort | uniq | while read logfile; do
        test -f "$logfile" || continue
        zipfile="${shared_log_dir}/$(basename $logfile).zip"
        log "INFO" "Criando o arquivo $zipfile a partir de $logfile..."
        cd $serverroot; zip -ql1 ${shared_log_dir}/${instancia_jboss}.zip $logfile; cd - > /dev/null
    done

    log "INFO" "Fim da transferência de logs."

    return 0

}

case $1 in
	log) copy_log;;
	*) log "ERRO" "O script somente admite o parâmetro 'log'.";;
esac
