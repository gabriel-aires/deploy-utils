#!/bin/bash
#
# Script para automatização dos deploys e disponibilização de logs do ambiente JBOSS / Linux.
#
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

# Utilização
if [ "$#" -ne '3' ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
	echo "Utilização: $(readlink -f $0) <nome_agente> <nome_tarefa> <lista_extensões>" && exit 1
fi

agent_name="$1"
task_name="$2"
file_types="$3"
pid="$$"
execution_mode="agent"

###### FUNÇÕES ######

function log () {	##### log de execução detalhado.

	echo -e "$(date +"%F %Hh%Mm%Ss") : $HOSTNAME : $(readlink -f $0) (${FUNCNAME[1]}) : $1 :  $2"

}

function end () {

	if [ -d "$tmp_dir" ]; then
		rm -f ${tmp_dir}/*
		rmdir ${tmp_dir}
	fi

	clean_locks

	exit "$1"
}

function set_dir () {

	# Encontra os diretórios de origem/destino com base na hierarquia definida em global.conf. IMPORTANTE: TODOS os parâmetros de configuração devem ser validados previamente.

	local raiz="$1"
	local dir_acima="$raiz"
	local set_var="$2"

	unset "$2"

	local fim=0
	local n=1
	local var_n="dir_$n"

	if [ "$(eval "echo \$$var_n")" == '' ];then
		fim=1
	else
 		local dir_n="$(eval "echo \$$var_n")"
		dir_n="$(eval "echo \$$dir_n")"
		local nivel=1
	fi

	while [ "$fim" -eq '0' ]; do

		dir_acima=$dir_acima/$dir_n

		((n++))
		var_n="dir_$n"

		if [ "$(eval "echo \$$var_n")" == '' ];then
			fim=1
		else
			dir_n="$(eval "echo \$$var_n")"
			dir_n="$(eval "echo \$$dir_n")"
			((nivel++))
		fi

	done

	if [ "$nivel" == "$qtd_dir" ]; then
		set_var="$set_var=$(find "$raiz" -iwholename "$dir_acima" 2> /dev/null)"
		eval $set_var
	else
		log "ERRO" "Parâmetros incorretos no arquivo '$local_conf'."
		continue
	fi

}

chk_dir () {

	if [ -d "$1" ] && [ -n "$2" ] && [ -n "$3" ]; then

		local root_dir="$1"
		local last_dir="$2"
		local ext_list="$3"
		local file_path_regex=''

		log "INFO" "Verificando a consistência dos diretórios de '$last_dir' em '$root_dir'..."

	    # eliminar da estrutura de diretórios subjacente os arquivos e subpastas cujos nomes contenham espaços.
	    find $root_dir/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rfv

	    # garantir integridade da estrutura de diretórios, eliminando subpastas inseridas incorretamente.
	    find $root_dir/* -type d | grep -Ei "^$root_dir/[^/]+/[^/]+" | grep -Eixv "^$root_dir/[^/]+/$last_dir$" | xargs -r -d "\n" rm -Rfv

	    # eliminar arquivos em local incorreto ou com extensão diferente das especificadas.
		file_path_regex="^$root_dir/[^/]+/$last_dir/[^/]+\."
		file_path_regex="$(echo "$file_path_regex" | sed -r "s|^(.*)$|\1$ext_list\$|ig" | sed -r "s: :\$\|$file_path_regex:g")"
		find "$root_dir" -type f | grep -Eixv "$file_path_regex" | xargs -r -d "\n" rm -fv

	else
		log "ERRO" "chk_dir: falha na validação dos parâmetros: $@"
		end 1
	fi

	return 0

}

function deploy_agent () {

	local file_path_regex=''

	if [ $(ls "${origem}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then

		chk_dir ${origem} "deploy" "$file_types"

    	# Verificar se há arquivos para deploy.

    	log "INFO" "Procurando novos pacotes..."

		file_path_regex="^.*\."
		file_path_regex="$(echo "$file_path_regex" | sed -r "s|^(.*)$|\1$file_types\$|ig" | sed -r "s: :\$\|$file_path_regex:g")"

    	find "$origem" -type f -regextype posix-extended -iregex "$file_path_regex" > $tmp_dir/arq.list

		if [ $(cat $tmp_dir/arq.list | wc -l) -lt 1 ]; then
    		log "INFO" "Não foram encontrados novos pacotes para deploy."
    	else
    		# Caso haja arquivos, verificar se o nome do pacote corresponde ao diretório da aplicação.

    		rm -f "$tmp_dir/remove_incorretos.list"
			touch "$tmp_dir/remove_incorretos.list"

    		while read l; do

    			pkg_name=$( echo $l | sed -r "s|^${origem}/[^/]+/deploy/([^/]+)\.[a-z0-9]+$|\1|i" )
    			app=$( echo $l | sed -r "s|^${origem}/([^/]+)/deploy/[^/]+\.[a-z0-9]+$|\1|i" )

    			if [ $(echo $pkg_name | grep -Ei "^$app" | wc -l) -ne 1 ]; then
    				echo $l >> "$tmp_dir/remove_incorretos.list"
    			fi

    		done < "$tmp_dir/arq.list"

    		if [ $(cat $tmp_dir/remove_incorretos.list | wc -l) -gt 0 ]; then
    			log "WARN" "Removendo pacotes em diretórios incorretos..."
    			cat "$tmp_dir/remove_incorretos.list" | xargs -r -d "\n" rm -fv
    		fi

    		# Caso haja pacotes, deve haver no máximo um pacote por diretório

    		find "$origem" -type f -regextype posix-extended -iregex "$file_path_regex" > $tmp_dir/arq.list

			rm -f "$tmp_dir/remove_versoes.list"
			touch "$tmp_dir/remove_versoes.list"

    		while read l; do

				pkg_name=$( echo $l | sed -r "s|^${origem}/[^/]+/deploy/([^/]+)\.[a-z0-9]+$|\1|i" )
    			dir=$( echo $l | sed -r "s|^(${origem}/[^/]+/deploy)/[^/]+\.[a-z0-9]+$|\1|i" )

    			if [ $( find $dir -type f | wc -l ) -ne 1 ]; then
    				echo $l >> $tmp_dir/remove_versoes.list
    			fi

    		done < "$tmp_dir/arq.list"

    		if [ $(cat $tmp_dir/remove_versoes.list | wc -l) -gt 0 ]; then
    			log "WARN" "Removendo pacotes com mais de uma versão..."
    			cat $tmp_dir/remove_versoes.list | xargs -r -d "\n" rm -fv
    		fi

			# O arquivo pkg.list será utilizado para realizar a contagem de pacotes existentes
			find "$origem" -type f -regextype posix-extended -iregex "$file_path_regex" > $tmp_dir/pkg.list

    		if [ $(cat $tmp_dir/pkg.list | wc -l) -lt 1 ]; then
				log "INFO" "Não há novos pacotes para deploy."
    		else
    			log "INFO" "Verificação do diretório ${remote_pkg_dir_tree} concluída. Iniciando processo de deploy dos pacotes abaixo."
    			cat $tmp_dir/pkg.list

				# A variável pkg_list foi criada para permitir a iteração entre a lista de pacotes, uma vez que o diretório temporário precisa ser limpo.
				pkg_list="$(find "$origem" -type f -regextype posix-extended -iregex "$file_path_regex")"
				pkg_list="$(echo "$pkg_list" | sed -r "s%(.)$%\1|%g")"

    			echo $pkg_list | while read -d '|' pkg; do

					#define variáveis a sereem utilizadas pelo agente durante o processo de deploy.
					export pkg
					export ext=$(echo $(basename $pkg) | sed -r "s|^.*\.([^\.]+)$|\1|" | tr '[:upper:]' '[:lower:]')
	    			export app=$(echo $pkg | sed -r "s|^${origem}/([^/]+)/deploy/[^/]+\.[a-z0-9]+$|\1|i" | tr '[:upper:]' '[:lower:]')
					export host=$(echo $HOSTNAME | cut -f1 -d '.')

					case $ext in
						war|ear|sar)
							rev=$(unzip -p -a $pkg META-INF/MANIFEST.MF | grep -i implementation-version | sed -r "s|^.+ (([[:graph:]])+).*$|\1|")
							;;
						*)
							rev=$(echo $(basename $pkg) | sed -r "s|^$app||i" | sed -r "s|$ext$||i" | sed -r "s|^[\.\-_]||")
							;;
					esac

					if [ -z "$rev" ]; then
						rev="N/A"
					fi

					export rev

					#### Diretórios onde serão armazenados os logs de deploy (define e cria os diretórios remote_app_history_dir e deploy_log_dir)
					set_app_history_dirs

					export remote_app_history_dir
					export deploy_log_dir

					#valida variáveis antes da chamada do agente.
					valid 'app' "Nome de aplicação inválido: $app" "continue" || continue
					valid 'host' "regex_hosts_$ambiente" "Host inválido para o ambiente $ambiente: $host" "continue" || continue

					#inicio deploy
					deploy_log_file=$deploy_log_dir/deploy_${host}.log
					qtd_log_inicio=$(cat $log | wc -l)
					rm -f $tmp_dir/*
					$agent_script 'deploy'
					qtd_log_fim=$(cat $log | wc -l)
					qtd_info_deploy=$(( $qtd_log_fim - $qtd_log_inicio ))
					tail -n ${qtd_info_deploy} $log > $deploy_log_file

				done < "$tmp_dir/pkg.list"

			fi

		fi

	else
		log "ERRO" "Não foram encontrados os diretórios das aplicações em $origem"
	fi

}

function log_agent () {

	if [ $(ls "${destino}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then

		chk_dir "$destino" "log" "$file_types"

		app_list="$(find $destino/* -type d -iname 'log' -print | sed -r "s|^${destino}/([^/]+)/log|\1|ig")"
		app_list=$(echo "$app_list" | sed -r "s%(.)$%\1|%g" | tr '[:upper:]' '[:lower:]')

		echo $app_list | while read -d '|' app; do

			destino_log=$(find "$destino/" -type d -iwholename "$destino/$app/log" 2> /dev/null)

			if [ -d "$destino_log" ]; then

				export destino_log
				export app

				valid 'app' 'Nome de aplicação inválido.' "continue" || continue

				rm -f $tmp_dir/*
				$agent_script 'log'
				cp -f $log "$destino_log/cron.log"
				unix2dos "$destino_log/cron.log" > /dev/null 2>&1

			else
				log "ERRO" "O diretório para cópia de logs da aplicação $app não foi encontrado".
			fi

		done

	else
		log "ERRO" "Não foram encontrados os diretórios das aplicações em $destino"
	fi

}


###### INICIALIZAÇÃO ######
trap "end 1; exit" SIGQUIT SIGINT SIGHUP SIGTERM

# Valida o arquivo global.conf e carrega configurações
arq_props_global="${install_dir}/conf/global.conf"
test -f "$arq_props_global" || exit 1
dos2unix "$arq_props_global" > /dev/null 2>&1
chk_template "$arq_props_global"
source "$arq_props_global" || exit 1

# cria diretório temporário
tmp_dir="$work_dir/$pid"
valid 'tmp_dir' 'Caminho inválido para armazenamento de diretórios temporários' && mkdir -p $tmp_dir

# cria diretório de logs e expurga logs do mês anterior.
valid 'log_dir' 'Caminho inválido para o diretório de armazenamento de logs'
log="$log_dir/deploy-$(date +%F).log"
mkdir -p $log_dir && touch $log
echo "" >> $log
find $log_dir -type f | grep -v $(date "+%Y-%m") | xargs rm -f

# cria diretório de locks
valid 'lock_dir' 'Caminho inválido para o diretório de lockfiles do agente.' && mkdir -p $lock_dir

#valida caminho para diretórios do servidor e argumentos do script
erro=false

valid 'agent_name' "Nome inválido para o agente." 'continue' >> $log 2>&1 || erro=1
valid 'task_name' "Nome inválido para a tarefa." 'continue' >> $log 2>&1 || erro=1
valid 'file_types' "Lista de extensões inválida." 'continue' >> $log 2>&1 || erro=1

valid 'remote_pkg_dir_tree' 'regex_remote_dir' 'Caminho inválido para o repositório de pacotes.' 'continue' >> $log 2>&1 || erro=1
valid 'remote_log_dir_tree' 'regex_remote_dir' 'Caminho inválido para o diretório raiz de cópia dos logs.' 'continue' >> $log 2>&1 || erro=1
valid 'remote_lock_dir' 'regex_remote_dir' 'Caminho inválido para o diretório de lockfiles do servidor' 'continue' >> $log 2>&1 || erro=1
valid 'remote_history_dir' 'regex_remote_dir' 'Caminho inválido para o diretório de gravação do histórico' 'continue' >> $log 2>&1 || erro=1
valid 'remote_app_history_dir_tree' 'regex_remote_dir' 'Caminho inválido para o histórico de deploy das aplicações' 'continue' >> $log 2>&1 || erro-1

test ! -d "$remote_pkg_dir_tree" && log 'ERRO' 'Caminho para o repositório de pacotes inexistente.' >> $log 2>&1 && erro=1
test ! -d "$remote_log_dir_tree" && log 'ERRO' 'Caminho para o diretório raiz de cópia dos logs inexistente.' >> $log 2>&1 && erro=1
test ! -d "$remote_lock_dir" && log 'ERRO' 'Caminho para o diretório de lockfiles do servidor não encontrado' >> $log 2>&1 && erro=1
test ! -d "$remote_history_dir" && log 'ERRO' 'Caminho para o diretório de gravação do histórico não encontrado' >> $log 2>&1 && erro=1
test ! -d "$remote_app_history_dir_tree" && log 'ERRO' 'Caminho para o histórico de deploy das aplicações não encontrado' >> $log 2>&1 && erro=1

if $erro; then
	end 1
else
	unset erro
fi

# Cria lockfiles.
mklist	"$file_types" "$tmp_dir/ext_list"
while read extension; do
	lock "$agent_name $task_name $extension" "Uma tarefa concorrente já está em andamento. Aguarde..."
done < $tmp_dir/ext_list

# Identifica script e diretório de configuração do agente.
dir_props_local="${install_dir}/conf/$agent_name"
agent_script="${install_dir}/sh/$agent_name.sh"

if [ -d $dir_props_local ]; then
	arq_props_local=$(find "$dir_props_local" -type f -iname "*.conf" -print)
	arq_props_local=$(echo "$arq_props_local" | sed -r "s%(.)$%\1|%g")
else
	log "ERRO" "O diretório de configuração do agente não foi encontrado."
	end 1
fi

if [ ! -x $agent_script ]; then
	log "ERRO" "O arquivo executável correspondente ao agente $agent_name não foi identificado."
	end 1
fi

# verifica o(s) arquivo(s) de configuração do agente.
if [ $(echo "$arq_props_local" | sed -r "s%|%%g" | wc -w) -eq 0 ]; then
	end 1
fi

# Executa a tarefa especificada para cada arquivo de configuração do agente.
echo $arq_props_local | while read -d '|' local_conf; do

	# Valida o arquivo de configurações $local_conf
	chk_template "$local_conf" 'local' 'continue' >> $log 2>&1 || continue
	source "$local_conf" || continue

	# validar parâmetro ambiente do arquivo $local_conf:
	valid 'ambiente' "Nome inválido para o ambiente." "continue" >> $log 2>&1 || continue

	# verificar se o caminho para obtenção dos pacotes / gravação de logs está disponível.
	set_dir "$remote_pkg_dir_tree" 'origem' >> $log 2>&1
	set_dir "$remote_log_dir_tree" 'destino' >> $log 2>&1

	if [ $( echo "$origem" | wc -w ) -ne 1 ] || [ ! -d "$origem" ] || [ $( echo "$destino" | wc -w ) -ne 1 ] || [ ! -d "$destino" ]; then
		log "ERRO" "O caminho para o diretório de pacotes / logs não foi encontrado ou possui espaços." >> $log 2>&1
		continue
	fi

	# exportar funções e variáveis necessárias ao agente. Outras variáveis serão exportadas diretamente a partir das funções log_agent e deploy_agent

	export -f 'log'
	export -f 'write_history'
	export 'execution_mode'
	export 'interactive'
	export 'lock_history'
	export 'remote_lock_dir'
	export 'remote_history_dir'
	export 'tmp_dir'

	while read l ; do
		if [ $(echo $l | grep -Ex "^[a-zA-Z0-9_]+='?[a-zA-Z0-9_/\-]+'?$" | wc -l) -eq 1 ]; then
			conf_var=$(echo "$l" | sed -r "s|=.*$||")
			export $conf_var
		fi
	done < $local_conf

	# executar agente.

	case $task_name in
		'log')
			if [ "$(cat $agent_script | sed -r 's|"||g' | sed -r "s|'||g" | grep -E '^[^[:graph:]]*log\)' | wc -l)" -eq 1 ]; then
				log_agent >> $log 2>&1
			else
				log "ERRO" "O script $agent_script não aceita o argumento 'log'." >> $log 2>&1
				continue
			fi
			;;
		'deploy')
			if [ "$(cat $agent_script | sed -r 's|"||g' | sed -r "s|'||g" | grep -E '^[^[:graph:]]*deploy\)' | wc -l)" -eq 1 ]; then
				deploy_agent >> $log 2>&1
			else
				log "ERRO" "O script $agent_script não aceita o argumento 'deploy'." >> $log 2>&1
				continue
			fi
			;;
	esac

done

end 0
