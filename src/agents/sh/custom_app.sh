#!/bin/bash
task="$1"                           #deploy, log

function config_deployment_defaults () {
    state="r"                                   #r (read), w (write), x (execute)
    simulation=false                    
    update=true                         
    enable_deletion="${rsync_deletion:=false}"
    force_uid="${force_uid:=''}"
    force_gid="${force_gid:=''}"
    rsync_opts="${rsync_opts:='--recursive --checksum --inplace --safe-links --exclude=.git/***'}"
    rsync_bkp_opts='--owner --group --perms --times'               
    extra_opts=""
    rsync_log="$deploy_log_dir/rsync-$host.log"
    deployment_report="$deploy_log_dir/deployment-report-$host.txt"    
    wait="timeout -s KILL"                      #prepend to commands
    timeout_before="${timeout_before:=300}"     #time in seconds
    timeout_deploy="${timeout_deploy:=3600}"
    timeout_after="${timeout_after:=300}"    
}

function config_simulation () {
    [[ $rev =~ !$ ]] && simulation=true && extra_opts="$extra_opts --dry-run" 
}

function config_rollback () {
    [ "$rev" == "rollback" ] && update=false && extra_opts="$extra_opts $rsync_bkp_opts"
}

function prepare_checkout () {
    if $update; then
        try_catch "mkdir -p $tmp_dir/$app" || finalize 1
        try_catch "unzip $pkg -d $tmp_dir/$app/" || finalize 1
        src_path="$(join_path $tmp_dir / $app / $app_root)"
        dir_test="$(chk_path $src_path && echo found || echo not_found)" 
        try_catch "assert 'app_root $src_path' $dir_test found" || finalize 1
    else
        #file $app-rollback.md
        log "INFO" "Descrição do rollback:"
        cat "$pkg"
        src_path="$bkp_path"
    fi    
}

function prepare_filters () {
    filter="$tmp_dir/rsync_filters.txt"
    rollback_filter="$bkp_path/rsync_filters_${app}_${ambiente}.txt"
    touch $filter

    if ! $update && [ -f "$rollback_filter" ]; then
        cat "$rollback_filter" > "$filter"

    elif [ -f "$src_path/.gitignore" ]; then
        try_catch "dos2unix -n $src_path/.gitignore $filter" || finalize 1
        try_catch "sed -r -i /^$|^[[:blank:]]|^#/d $filter" || finalize 1

        if [ "$app_root" != "/" ]; then
            pattern=$(echo "$app_root" | sed -r "s|^/||;s|/$||")
            sed -i -r "s|^(! +)?/$pattern(/.+)|\1\2|;s|^(! +)?($pattern)(/.+)|\1\2\3\n\1\3|" "$filter"
        fi

        sed -i -r "s|^(! +)|+ |" $filter    #includes        
        sed -i -r "s|^([^+])|- \1|" $filter #excludes
    fi

    try_catch "cp $filter $deploy_log_dir/" || finalize 1
    rsync_opts="$rsync_opts --filter='. $filter'"

    return 0
}

function prepare_backup () {

    if $update; then
        try_catch "rm -Rf $bkp_path" || finalize 1
        try_catch "mkdir -p $bkp_path" || finalize 1
        try_catch "rsync $rsync_bkp_opts $rsync_opts $install_path/ $bkp_path/" || finalize 1

        #### backup deploy-filter ###
        try_catch "cp $filter $rollback_filter" || finalize 1
    fi
}

function sync_files () {

    try_catch "$wait $timeout_deploy rsync $rsync_opts $extra_opts --log-file=$rsync_log $src_path/ $install_path/" || finalize 1
    set_state 'r'

    added="$(grep -E "^>f\+" $rsync_log | wc -l)"
    deleted="$(grep -E "^\*deleting .*[^/]$" $rsync_log | wc -l)"
    modified="$(grep -E "^>f[^\+]" $rsync_log | wc -l)"
    new_folder="$(grep -E "^cd\+" $rsync_log | wc -l)"
    old_folder="$(grep -E "^\*deleting .*/$" $rsync_log | wc -l)"
    total_arq=$(( $added + $deleted + $modified ))
    total_dir=$(( $new_folder + $old_folder ))
    total_del=$(( $deleted + $old_folder ))

    echo -e "\nLog das modificacoes gravado no arquivo $(basename $rsync_log)\n" > $deployment_report
    echo -e "Arquivos adicionados ............... $added " >> $deployment_report
    echo -e "Arquivos excluidos ................. $deleted" >> $deployment_report
    echo -e "Arquivos modificados ............... $modified" >> $deployment_report
    echo -e "Diretórios criados ................. $new_folder" >> $deployment_report
    echo -e "Diretórios removidos ............... $old_folder\n" >> $deployment_report
    echo -e "Total de operações de arquivos ..... $total_arq" >> $deployment_report
    echo -e "Total de operações de diretórios ... $total_dir" >> $deployment_report
    echo -e "Total de operações de exclusão ..... $total_del\n" >> $deployment_report

    log "INFO" "Relatório de implantação ($app: $rev)..."
    cat $deployment_report
    
}

function set_owner () {
    own_cmd=""
    own_args="$(echo "$force_uid:$force_gid" | sed -r 's/^://;s/:$//')"
    option "$force_uid" && own_cmd="chown" 
    option "$force_gid" && own_cmd="${own_cmd:=chgrp}"
    if option "$own_cmd"; then
        log "INFO" "Atribuindo usuário/grupo..."
        set_state 'x'
        try_catch "$own_cmd -R $own_args $install_path" || finalize 1
        set_state 'r'
    fi
}

function run_script () {
    log "INFO" "Verificando script de ${1}install..."
    case "$1" in
        'pre') option "$script_before" && set_state 'x' && { try_catch "$wait $timeout_before $script_before" || finalize 1 ; } && set_state 'r';;
        'post') option "$script_after" && set_state 'x' && { try_catch "$wait $timeout_after $script_after" || finalize 1 ; } && set_state 'r';;
        *) return 1;;
    esac
}

function unrecoverable () {
    log "ERRO" "Falha durante execução de '$last_command'. Verificar!"
}

function write_recover () {
    if $update; then
        log "ERRO" "Falha durante a escrita. Revertendo alterações..."
        rsync $rsync_bkp_opts $rsync_opts $bkp_path/ $install_path/ && rm -rf $bkp_path && log "INFO" "Rollback concluído."
    else
        unrecoverable    
    fi    
}

function finalize () {
    status="$1"
    if [ "$status" -ne 0 ]; then
        if [ "$state" == 'w' ]; then
            write_recover
        elif [ "$state" == 'x' ]; then
            unrecoverable
        fi
        log "ERRO" "Rotina concluída com erro(s)." && exit "$status"
    else
        log "INFO" "Rotina concluída com sucesso." && exit "$status"
    fi
}

function deploy_pkg () {

    #configure
    log "INFO" "Validando configurações..."
    try_catch "chk_path $install_path" || finalize 1
    try_catch "chk_path $bkp_path" || finalize 1
    try_catch "starts_with $app_root /" || finalize 1
    option "$timeout_before" && { try_catch "chk_num $timeout_before" || finalize 1 ; }
    option "$timeout_deploy" && { try_catch "chk_num $timeout_deploy" || finalize 1 ; }
    option "$timeout_after" && { try_catch "chk_num $timeout_after" || finalize 1 ; }
    option "$script_before" && { try_catch "chk_exec $script_before" || finalize 1 ; }
    option "$script_after" && { try_catch "chk_exec $script_after"  || finalize 1 ; }
    option "$rsync_opts" && { try_catch "starts_with $rsync_opts -" || finalize 1 ; }
    option "$enable_deletion" && { try_catch "chk_bool $rsync_deletion" || finalize 1 ; }
    option "$force_uid" && { try_catch "chk_arg $force_uid" || finalize 1 ; }
    option "$force_gid" && { try_catch "chk_arg $force_gid" || finalize 1 ; }
    config_deployment_defaults
    config_simulation
    config_rollback

    #prepare
    prepare_checkout
    prepare_filters

    #deploy
    if ! $simulation; then
        log "INFO" "Criando backup..."
        prepare_backup
        run_script 'pre'
        log "INFO" "Iniciando transferência dos arquivos..."
        set_state 'w'
        sync_files
        set_owner
        run_script 'post'
        write_history "Deploy concluído com sucesso" "1"
    else
        log "INFO" "Simulação de deploy..."
        sync_files
    fi 

    finalize 0
}

case "$task" in
    log) copy_log;;
    deploy) deploy_pkg;;
    *) log "ERRO" "O script somente admite os parâmetros 'deploy' ou 'log'.";;
esac
