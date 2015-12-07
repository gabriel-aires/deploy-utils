#!/bin/bash
#
# Script para automatização dos deploys e disponibilização de logs do ambiente JBOSS / Linux.
#
agent_name=$1

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

###### FUNÇÕES ######

function log () {

	##### LOG DE DEPLOY DETALHADO ####

	echo -e "$(date +"%F %Hh%Mm%Ss") : $HOSTNAME : $1 : $2"

}

function end () {

	if [ -d "$tmp_dir" ]; then
		rm -Rf ${tmp_dir}/*
	fi

	if [ "$edit_log" == "1" ]; then
		rm -f ${remote_lock_dir}/$history_lock_file
	fi

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
	local var_n="DIR_$n"

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
		var_n="DIR_$n"

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

	local raiz="$1"

        log "INFO" "Verificando a consistência da estrutura de diretórios em $raiz.."

    	# eliminar da estrutura de diretórios subjacente os arquivos e subpastas cujos nomes contenham espaços.
    	find $raiz/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rfv

    	# garantir integridade da estrutura de diretórios, eliminando subpastas inseridas incorretamente.
    	find $raiz/* -type d | grep -Ei "^$raiz/[^/]+/[^/]+" | grep -Eixv "^$raiz/[^/]+/deploy$|^$raiz/[^/]+/log$" | xargs -r -d "\n" rm -Rfv

    	# eliminar arquivos em local incorreto ou com extensão diferente de .war / .ear / .log
    	find "$raiz" -type f | grep -Eixv "^$raiz/[^/]+/deploy/[^/]+\.[ew]ar$|^$raiz/[^/]+/log/[^/]+\.log$|^$raiz/[^/]+/log/[^/]+\.zip$" | xargs -r -d "\n" rm -fv

}

###### INICIALIZAÇÃO ######

trap "end 1; exit" SIGQUIT SIGINT SIGHUP SIGTERM

find_install_dir

arq_props_global="${install_dir}/conf/global.conf"
dir_props_local="${install_dir}/conf/$agent_name"
arq_props_local=$(find "$dir_props_local" -type f -iname "*.conf" -print)
arq_props_local=$(echo "$arq_props_local" | sed -r "s%(.)$%\1|%g")

# Verifica se o arquivo global.conf atende ao template correspondente.

if [ -f "$arq_props_global" ]; then
	dos2unix "$arq_props_global" > /dev/null 2>&1
else
	exit 1
fi

if [ "$(grep -v --file=${install_dir}/template/global.template $arq_props_global | wc -l)" -ne "0" ] \
	|| [ $(cat $arq_props_global | sed 's|"||g' | grep -Ev "^#|^$" | grep -Ex "^DIR_.+='?AMBIENTE'?$" | wc -l) -ne "1" ];
then
	exit 1
fi

# Carrega constantes.

source "$arq_props_global" || exit 1

# Se houver mais de um PID referente ao script, a tarefa já está em andamento.

if [ "$(pgrep -f $0)" != "$$" ]; then
    echo "Tarefa em andamento... Aguarde."
    exit 0
fi

# cria diretório temporário.

if [ ! -z "$tmp_dir" ]; then
	mkdir -p $tmp_dir
else
	exit 0
fi

# cria pasta de logs / expurga logs de deploy do mês anterior.

if [ ! -z "$log_dir" ]; then
	mkdir -p $log_dir
	touch $log
	echo "" >> $log
	find $log_dir -type f | grep -v $(date "+%Y-%m") | xargs rm -f
else
	exit 0
fi

# Executa deploys e copia logs das instâncias jboss

if [ $(echo "$arq_props_local" | wc -w) -ne 0 ]; then
	source $agent_name.sh >> $log 2>&1
else
	exit 1
fi
