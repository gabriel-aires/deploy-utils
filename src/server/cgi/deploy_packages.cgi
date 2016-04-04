#!/bin/bash

### Inicialização
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

function parse_multipart_form() { #argumentos: nome de arquivo com conteúdo do POST

    #atribui variáveis do formulário e prepara arquivos carregados para o servidor

    local boundary="$(echo "$CONTENT_TYPE" | sed -r "s|multipart/form-data; +boundary=||" | sed -r 's|\-|\\-|g')"
    local part_boundary="\-\-$boundary"
    local end_boundary="\-\-$boundary\-\-"
    local next_boundary=''
    local input_file="$1"
    local input_size="$(cat "$input_file" | wc -l)"
    local file_begin=''
    local file_end=''
    local file_cmd=()
    local file_name=''
    local var_name=''
    local var_set=false
    local i=0
    local n=0

    while [ "$i" -lt "$input_size" ]; do

        ((i++))
        line="$(sed -n "${i}p" "$input_file" | sed -r "s|\r$||")"

        if echo "$line" | grep -Ex "$part_boundary|$end_boundary" > /dev/null; then
            file_name=''
            file_begin=''
            file_end=''
            var_name=''
            var_set=false

        elif echo "$line" | grep -Ex "Content\-Disposition: form\-data; name=[^;]*; filename=.*" > /dev/null; then
            var_name="$(echo "$line" | sed -r "s|Content\-Disposition: form\-data; name=([^;]*); filename=.*|\1|" | sed -r "s|\"||g")"
            file_name="$(echo "$line" | sed -r "s|Content\-Disposition: form\-data; name=[^;]*; filename=||" | sed -r "s|\"||g")"
            file_name="$tmp_dir/$(basename $file_name)"
            eval "$var_name=$file_name"
            var_set=true
            file_begin=$((i+3)) #i+1: content-type, i+2: '', i+3: file_begin
            next_boundary=$(sed -n "${file_begin},${input_size}p" "$input_file" | cat -t | grep -En "^$part_boundary" | head -n 1 | cut -d ':' -f1)
            next_boundary=$((next_boundary+file_begin-1))
            file_end=$((next_boundary-1))
            i="$file_end"
            file_cmd[$n]="sed -n '${file_begin},$((file_end-1))p' $input_file > $file_name && sed -rn '${file_end}s|\r$||p' $input_file | tr -d '\n' >> $file_name"
            ((n++))

        elif echo "$line" | grep -Ex "Content\-Disposition: form\-data; name=.*" > /dev/null; then
            var_name="$(echo "$line" | sed -r "s|Content\-Disposition: form\-data; name=||" | sed -r "s|\"||g")"

        elif [ -n "$line" ]; then
            ! $var_set && test -n "$var_name" && eval "$var_name=$line" && var_set=true

        fi

    done

    if [ $n -gt 0 ]; then
        for i in $(seq 0 $n); do
            test -n "${file_cmd[$i]}" && eval ${file_cmd[$i]}
        done
    fi

}

function submit_deploy() {

    if [ "$proceed" != "$proceed_view" ]; then
        return 1

    else
        local app_deploy_clearance="$tmp_dir/app_deploy_clearance"
        local env_deploy_clearance="$tmp_dir/env_deploy_clearance"
        local process_group=''
        local show_form=false

        rm -f $app_deploy_clearance $env_deploy_clearance

        { clearance "user" "$REMOTE_USER" "app" "$app" "write" && touch "$app_deploy_clearance"; } &
        process_group="$process_group $!"

        { clearance "user" "$REMOTE_USER" "ambiente" "$env" "write" && touch "$env_deploy_clearance"; } &
        process_group="$process_group $!"

        wait $process_group
        test -f $app_deploy_clearance && test -f $env_deploy_clearance && show_form=true

        if $show_form; then
            echo "      <p>"
            echo "          <form action=\"$start_page\" method=\"post\" enctype=\"multipart/form-data\">"
            echo "              <input type=\"hidden\" name=\"app\" value=\"$app\"></td></tr>"
            echo "              <input type=\"hidden\" name=\"env\" value=\"$env\"></td></tr>"
            echo "              <input type=\"file\" name=\"pkg\">"
            echo "              <p>"
            echo "                  <input type=\"submit\" name=\"proceed\" value=\"$proceed_deploy\">"
            echo "              </p>"
            echo "          </form>"
            echo "      </p>"
        else
            echo "      <p><b>Acesso negado.</b></p>"
        fi

    fi

    return 0

}

function end() {
    test "$1" == "0" || echo "      <p><b>Operação inválida.</b></p>"
    web_footer

    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -f $tmp_dir/*
        rmdir $tmp_dir
    fi

    test -n "$sleep_pid" && kill "$sleep_pid" &> /dev/null
    clean_locks
    wait &> /dev/null

    exit $1
}

trap "end 1" SIGQUIT SIGINT SIGHUP
mkdir $tmp_dir

### Cabeçalho
web_header

# Inicializar variáveis e constantes
parsed=false

if [ "$REQUEST_METHOD" == "POST" ]; then
    if [ "$CONTENT_TYPE" == "application/x-www-form-urlencoded" ]; then
        test -n "$CONTENT_LENGTH" && read -n "$CONTENT_LENGTH" POST_STRING
        arg_string="&$(web_filter "$POST_STRING")&"
        app=$(echo "$arg_string" | sed -rn "s/^.*&app=([^\&]+)&.*$/\1/p")
        env=$(echo "$arg_string" | sed -rn "s/^.*&env=([^\&]+)&.*$/\1/p")
        proceed=$(echo "$arg_string" | sed -rn "s/^.*&proceed=([^\&]+)&.*$/\1/p")
        parsed=true

    elif echo "$CONTENT_TYPE" | grep -Ex "multipart/form-data; +boundary=.*" > /dev/null; then
        cat > "$tmp_dir/POST_CONTENT"
        parse_multipart_form "$tmp_dir/POST_CONTENT"
        rm -f "$tmp_dir/POST_CONTENT"
        parsed=true

    fi
fi

mklist "$ambientes" "$tmp_dir/lista_ambientes"
proceed_view="Continuar"
proceed_deploy="Deploy"

if ! $parsed; then

    # Formulário deploy
    echo "      <p>"
    echo "          <form action=\"$start_page\" method=\"post\">"
    # Sistema...
    echo "              <p>"
    echo "      		    <select class=\"select_default\" name=\"app\">"
    echo "		        	<option value=\"\" selected>Sistema...</option>"
    find $upload_dir/ -mindepth $((qtd_dir+1)) -maxdepth $((qtd_dir+1)) -type d | xargs -I{} -d '\n' basename {} | sort | uniq | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|" 2> /dev/null
    echo "		            </select>"
    echo "              </p>"
    # Ambiente...
    echo "              <p>"
    echo "      		<select class=\"select_default\" name=\"env\">"
    echo "		        	<option value=\"\" selected>Ambiente...</option>"
    cat $tmp_dir/lista_ambientes | sort | sed -r "s|(.*)|\t\t\t\t\t<option>\1</option>|"
    echo "		        </select>"
    echo "              </p>"
    # Submit
    echo "              <p>"
    echo "              <input type=\"submit\" name=\"proceed\" value=\"$proceed_view\">"
    echo "              </p>"
    echo "          </form>"
    echo "      </p>"

elif [ -n "$app" ] && [ -n "$env" ] && [ -n "$proceed" ]; then

    case "$proceed" in

        "$proceed_view")

            find $upload_dir/ -mindepth $((qtd_dir+2)) -maxdepth $((qtd_dir+2)) -type d -regextype posix-extended -iregex "^$upload_dir/$env/.*/$app/deploy$" > $tmp_dir/deploy_path
            test "$(cat $tmp_dir/deploy_path | wc -l)" -eq 0 && echo "<p><b>Nenhum caminho de deploy encontrado para a aplicação '$app' no ambiente '$env'.</b></p>" && end 1

            ### Visualizar parâmetros de deploy
            echo "      <p>"
            echo "          Sistema:"
            echo "          <ul>"
            echo "              <li>$app</li>"
            echo "          </ul>"
            echo "          Ambiente:"
            echo "          <ul>"
            echo "              <li>$env</li>"
            echo "          </ul>"
            echo "          Caminho:"
            echo "          <ul>"
            cat $tmp_dir/deploy_path | sed -r "s|^$upload_dir/(.*)$|<li>\1</li>|"
            echo "          </ul>"
            echo "      </p>"

            submit_deploy
            ;;

        "$proceed_deploy")

            test ! -f "$pkg" && echo "<p><b>Nenhum arquivo selecionado para upload.</b></p>" && end 1
            lock "package_${app}_${env}" "Há outro deploy da aplicação $app no ambiente $env em execução. Tente novamente."

            test -n "$REMOTE_USER" && user_name="$REMOTE_USER" || user_name="$(id --user --name)"
            pkg_name=$(basename $pkg | sed -r "s|\.[^\.]+$||")
            pkg_ext=$(basename $pkg | sed -r "s|^.*\.([^\.]+)$|\1|")
            pkg_md5="$(md5sum "$pkg" | cut -d ' ' -f1)"
            pkg_new="$pkg_name%user_$user_name%md5_$pkg_md5%.$pkg_ext"

            find $upload_dir/ -mindepth $((qtd_dir+2)) -maxdepth $((qtd_dir+2)) -type d -regextype posix-extended -iregex "^$upload_dir/$env/.*/$app/deploy$" | xargs -d '\n' -I{} cp -f $pkg {}/$pkg_new

            echo "      <p><b> CHECKSUM DO ARQUIVO: $pkg_md5</b></p>"
            echo "      <p> Upload do pacote concluído. Favor aguardar a execução do agente de deploy nos hosts correspondentes.</p>"
            ;;

    esac

else
    echo "      <p><b>Erro. Os parâmetro 'Sistema' e 'Ambiente' devem ser preenchidos.</b></p>"
fi

end 0
