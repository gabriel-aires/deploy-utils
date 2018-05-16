#!/bin/bash

function copy_log () {

    log "INFO" "Buscando logs do servidor apache..."

    regex[serverroot_directive]="^[[:blank:]]*ServerRoot [^[:blank:]]+$"
    regex[include_directive]="^[[:blank:]]*Include(Optional)? [^;\&\$\` ]+\.conf$"
    regex[log_directive]="^[[:blank:]]*(Custom|Error|Global|Script|Transfer)Log [^;\&\$\` ]+( .+)*$"

    test ! -f "$apache_configuration" && log "ERRO" "Arquivo de configuração do apache não identificado. Abortando..." && return 1
    serverroot="$(grep -Ex "${regex[serverroot_directive]}" "$apache_configuration" | tail -n 1 | sed -r "s|^[[:blank:]]*||" | cut -d ' ' -f2 | sed -r 's|\"||g' | sed -r "s|\'||g")"
    test ! -d "$serverroot" && log "ERRO" "Diretório raiz do apache não identificado. Abortando..." && return 1

    working_dir="$(pwd)"
    cd $serverroot

    grep -Ex "${regex[include_directive]}" "$apache_configuration" | sed -r "s|^[[:blank:]]*||" | cut -d ' ' -f2 | sed -r 's|\"||g' | sed -r "s|\'||g" > $tmp_dir/apache_includes.list
    grep -Ex "${regex[log_directive]}" "$apache_configuration" | sed -r "s|^[[:blank:]]*||" | cut -d ' ' -f2 | sed -r 's|\"||g' | sed -r "s|\'||g" > $tmp_dir/apache_logs.list

    cat $tmp_dir/apache_includes.list | while read apache_includes; do
        grep -Exh "${regex[log_directive]}" $apache_includes | sed -r "s|^[[:blank:]]*||" | cut -d ' ' -f2 | sed -r 's|\"||g' | sed -r "s|\'||g" >> $tmp_dir/apache_logs.list
    done

    log "INFO" "Separando logs da aplicação $app..."

    sort $tmp_dir/apache_logs.list | uniq | while read logpath; do

        logname="$(basename $logpath)"
        zipfile="${shared_log_dir}/$logname.zip"
        zippipe="$tmp_dir/$logname"
        mkfifo "$zippipe"
        log "INFO" "Criando o arquivo $zipfile..."

        ls $logpath* | while read logfile; do
            test ! -f "$logfile" && log "ERRO" "'$logfile' não é um arquivo. Continuando..." && continue
            test "$(file -bi "$logfile" | cut -d / -f1)" != 'text' && log "INFO" "'$logfile' não é um arquivo de texto. Continuando..." && continue
            log "INFO" "Adicionando o arquivo $logfile..."
            grep -F "$app" "$logfile" > "$zippipe" & zip --fifo -q -j -l -1 "$zipfile" "$zippipe" # a função compress não foi utilizada devido à necessidade de utilização de um named pipe
        done

    done

    log "INFO" "Fim da transferência de logs."
    cd "$working_dir"

    return 0

}

case $1 in
	log) copy_log;;
	*) log "ERRO" "O script somente admite o parâmetro 'log'.";;
esac
