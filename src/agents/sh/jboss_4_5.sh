#!/bin/bash

function jboss_script_init () {

	##### LOCALIZA SCRIPT DE INICIALIZAÇÃO DA INSTÂNCIA JBOSS #####

	local caminho_jboss=$1
	local instancia=$2

	if [ -n "$caminho_jboss" ] && [ -n "$instancia" ] && [ -d  "${caminho_jboss}/server/${instancia}" ]; then

		unset script_init
		find /etc/init.d/ -type f -iname '*jboss*' > "$tmp_dir/scripts_jboss.list"

		#verifica todos os scripts de jboss encontrados em /etc/init.d até localizar o correto.
		while read script_jboss && [ -z "$script_init" ]; do

			#verifica se o script corresponde à instalação correta do JBOSS e se aceita os argumentos 'start' e 'stop'
			if [ -n "$(grep -E '^([^[:graph:]])+?start[^A-Za-z0-9_\-]?' "$script_jboss" | head -1)" ] \
				&& [ -n "$(grep -E '^([^[:graph:]])+?stop[^A-Za-z0-9_\-]?' "$script_jboss" | head -1)" ] \
				&& [ -n "$(grep -F "$caminho_jboss" "$script_jboss" | head -1)" ];
			then

				#teste 1: retorna a primeira linha do tipo .../server/...

				local linha_script=$(grep -Ex "^[^#]+[\=].*[/\$].+/server/[^/]+/.*$" "$script_jboss" | head -1 )
				local teste_script=1

				#teste 2: retorna a primeira linha onde foi utilizada a variável $JBOSS_CONF

				if [ -z "$linha_script" ]; then
					linha_script=$(grep -Ex '^.*\$JBOSS_CONF.*$' "$script_jboss" | head -1 )
					teste_script=2
				fi

				if [ -n "$linha_script" ]; then

					case $teste_script in
						1) local jboss_conf=$(echo "$linha_script" | sed -r "s|^.*/server/([^/]+).*$|\1|");;
						2) local jboss_conf='$JBOSS_CONF';;
					esac

					#Se a instância estiver definida como uma variável no script, o loop a seguir tenta encontrar o seu valor em até 3 iterações.

					local var_jboss_conf=$( echo "$jboss_conf" | grep -Ex "^\\$.*$")
					local i='0'

					while [ -n "$var_jboss_conf" ] && [ "$i" -lt '3' ]; do

						#remove o caractere '$', restando somente o nome da variável
						var_jboss_conf=$(echo "$var_jboss_conf" | sed -r "s|^.||")

						#encontra a linha onde a variável foi setada e retorna a string após o caractere =, sem aspas
						jboss_conf=$(grep -Ex "^$var_jboss_conf=.*$" "$script_jboss" | head -1 | sed 's|"||g' | sed "s|'||g" | sed -r "s|^$var_jboss_conf=([[:graph:]]+).*$|\1|" )

						#verificar se houve substituição de parâmetros
						if [ $(echo "$jboss_conf" | sed 's|}|¨|' | sed 's|{|¨|' | grep -Ex "^\\$¨$var_jboss_conf[:=\-]+(\\$)?[A-Za-z0-9_]+¨.*$" | wc -l) -ne 0 ]; then
							jboss_conf=$(echo "$jboss_conf" | sed 's|^..||' | sed 's|}.*$||' | sed -r "s|$var_jboss_conf[:=\-]+||")
						fi

						#atualiza condições para entrada no loop.
						var_jboss_conf=$( echo "$jboss_conf" | grep -Ex "^\\$.*$")
						((i++))

					done

					#verifica se o script encontrado corresponde à instância desejada.
					if [ -d "${caminho_jboss}/server/${jboss_conf}" ] && [ "$jboss_conf" == "$instancia" ]; then
						script_init=$script_jboss
					fi

				fi

			fi

		done < "$tmp_dir/scripts_jboss.list"

	else
		log "ERRO" "Parâmetros incorretos ou instância JBOSS não encontrada."
	fi

}

function deploy_pkg () {

	####### deploy #####

	find $caminho_instancias_jboss -type f -regextype posix-extended -iregex "$caminho_instancias_jboss/[^/]+/deploy/$app\.[ew]ar" > "$tmp_dir/old.list"

	if [ $( cat "$tmp_dir/old.list" | wc -l ) -eq 0 ]; then

		log "ERRO" "Deploy abortado. Não foi encontrado pacote anterior. O deploy deverá ser feito manualmente."
		write_history "Deploy abortado. Pacote anterior não encontrado."

	else

		while read old; do

			log "INFO" "O pacote $old será substituído".

			dir_deploy=$(echo $old | sed -r "s|^(${caminho_instancias_jboss}/[^/]+/deploy)/[^/]+\.[ew]ar$|\1|i")
			instancia_jboss=$(echo $old | sed -r "s|^${caminho_instancias_jboss}/([^/]+)/deploy/[^/]+\.[ew]ar$|\1|i")
			jboss_temp="$caminho_instancias_jboss/$instancia_jboss/tmp"
			jboss_temp=$(find $caminho_instancias_jboss -iwholename $jboss_temp)
			jboss_work="$caminho_instancias_jboss/$instancia_jboss/work"
			jboss_work=$(find $caminho_instancias_jboss -iwholename $jboss_work)
			jboss_data="$caminho_instancias_jboss/$instancia_jboss/data"
			jboss_data=$(find $caminho_instancias_jboss -iwholename $jboss_data)

			#tenta localizar o script de inicialização da instância e seta a variável $script_init, caso tenha sucesso
			jboss_script_init "$(dirname $caminho_instancias_jboss)" "$instancia_jboss"

			if [ -z "$script_init" ]; then
				log "ERRO" "Não foi encontrado o script de inicialização da instância JBoss. O deploy deverá ser feito manualmente."
				write_history "Deploy abortado. Script de inicialização não encontrado."
			else
				log "INFO" "Instância do JBOSS:     \t$instancia_jboss"
				log "INFO" "Diretório de deploy:    \t$dir_deploy"
				log "INFO" "Script de inicialização:\t$script_init"

				parar_instancia="$script_init stop"
				iniciar_instancia="$script_init start"

				eval $parar_instancia && wait

				if [ $(pgrep -f "$(dirname $caminho_instancias_jboss).*-c $instancia_jboss" | wc -l) -ne 0 ]; then
					log "ERRO" "Não foi possível parar a instância $instancia_jboss do JBOSS. Deploy abortado."
					write_history "Deploy abortado. Impossível parar a instância $instancia_jboss."
				else
					rm -f $old
					cp $pacote $dir_deploy/$(echo $app | tr '[:upper:]' '[:lower:]').$ext
					chown -R jboss:jboss $dir_deploy/

					if [ -d "$jboss_temp" ]; then
						rm -Rf $jboss_temp/*
					fi
					if [ -d "$jboss_work" ]; then
						rm -Rf $jboss_work/*
					fi
					if [ -d "$jboss_data" ]; then
						rm -Rf $jboss_data/*
					fi

					eval $iniciar_instancia && wait

					if [ $(pgrep -f "$(dirname $caminho_instancias_jboss).*-c $instancia_jboss" | wc -l) -eq 0 ]; then
						log "ERRO" "O deploy do arquivo $war foi concluído, porém não foi possível reiniciar a instância do JBOSS."
						write_history "Deploy não concluído. Erro ao reiniciar a instância $instancia_jboss."
					else
						log "INFO" "Deploy do arquivo $war concluído com sucesso!"
						write_history "Deploy concluído com sucesso na instância $instancia_jboss."
					fi

				fi

			fi

		done < "$tmp_dir/old.list"

		rm -f $pacote

	fi

}

function copy_log () {

	######## LOGS #########

	log "INFO" "Copiando logs da rotina e das instâncias JBOSS em ${caminho_instancias_jboss}..."

	rm -f "$tmp_dir/app_origem.list"
	find $caminho_instancias_jboss -type f -regextype posix-extended -iregex "$caminho_instancias_jboss/[^/]+/deploy/$app\.[ew]ar" > "$tmp_dir/app_origem.list" 2> /dev/null

	if [ $(cat "$tmp_dir/app_origem.list" | wc -l) -ne 0 ]; then

		while read caminho_app; do

			instancia_jboss=$(echo $caminho_app | sed -r "s|^${caminho_instancias_jboss}/([^/]+)/deploy/[^/]+\.[ew]ar$|\1|")
			server_log=$(find "${caminho_instancias_jboss}/${instancia_jboss}" -iwholename "${caminho_instancias_jboss}/${instancia_jboss}/log/server.log" 2> /dev/null)

			if [ $(echo $server_log | wc -l) -eq 1 ]; then
				cd $(dirname $server_log); zip -rql1 ${destino_log}/${instancia_jboss}.zip *; cd - > /dev/null
				cp -f $server_log "$destino_log/server_${instancia_jboss}.log"
				cp -f $log "$destino_log/cron.log"
				unix2dos "$destino_log/server_${instancia_jboss}.log" > /dev/null 2>&1
				unix2dos "$destino_log/cron.log" > /dev/null 2>&1
			else
				log "ERRO" "Não há logs da instância JBOSS correspondente à aplicação $app."
			fi

		done < "$tmp_dir/app_origem.list"

	else
		log "ERRO" "A aplicação $app não foi encontrada."
	fi

}

case $1 in
	deploy_pkg) deploy_pkg;;
	copy_log)	copy_log;;
esac
