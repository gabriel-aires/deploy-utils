#!/bin/bash

function deploy_pkg () {

	# encontrar local de implantação da aplicação $app
	app_deployed="$($wildfly_cmd --command="deployment-info --server-group=*" | grep "$app.$ext" | wc -l)"
	app_srvgroup="$($wildfly_cmd --command="deployment-info --name=$app.$ext" | grep "enabled" | cut -f1 -d ' ')"

	if [ $app_deployed -eq 1 ]; then

		echo "$app_srvgroup" | while read group; do

			log "INFO" "Removendo a aplicação $app do server-group $group"

			# parar a respectiva instância do servidor de aplicação
			$wildfly_cmd --command="undeploy $app.$ext --server-groups=$group" || exit 1

			# efetuar deploy do pacote $pkg no diretório de destino, renomeando-o para $app.$ext
			# reiniciar instância do servidor de aplicação
			$wildfly_cmd --command="deploy $pkg --name=$app.$ext --server-groups=$group" || exit 1

			# registrar sucesso do deploy no log do agente e no histórico de deploy
			log "INFO" "Deploy do arquivo $pkg realizado com sucesso no server-group $group"
			write_history "Deploy da aplicação $app realizado com sucesso no server-group $group"

		done

	else

		log "ERRO" "Não foi encontrado deploy anterior da aplicação $app" && exit 1

	fi

	# remover pacote do diretório de origem
	rm -f $pkg

}

function copy_log () {

	# registrar o início do processo de cópia de logs no log do agente
	log "INFO" "Buscando logs da aplicação $app..."

	# localizar logs específicos da aplicação $app e/ou do servidor de aplicação
	app_name="$($wildfly_cmd --command="deployment-info --server-group=*" | cut -f1 -d ' ' | grep -Ex "$app\..+")"
	app_deployed=$(echo $app_name | wc -l)
	app_srvgroup="$($wildfly_cmd --command="deployment-info --name=$app_name" | grep "enabled" | cut -f1 -d ' ')"

	if [ $app_deployed -eq 1 ]; then

		echo "$app_srvgroup" | while read group; do

			app_logs="$(find $wildfly_dir/ -type d -iwholename "*/servers/$group*/log" 2> /dev/null)"

			echo "$app_logs" | while read "app_log_dir"; do

				if [ -f $app_log_dir/server.log ]; then

					# copiar arquivos para o diretório $shared_log_dir
					log "INFO" "Copiando logs da aplicação $app no diretório $app_log_dir"
					hc_name=$(echo $app_log_dir | sed -r "s|$wildfly_dir||" | cut -f1 -d '/')
					cd $app_log_dir; zip -rql1 ${shared_log_dir}/${hc_name}_${group}.zip *; cd - > /dev/null
					cp -f $app_log_dir/server.log $shared_log_dir/server_${hc_name}_${group}.log

				else

					log "INFO" "Nenhum arquivo de log foi encontrado sob o diretório $app_log_dir"

				fi

			done

		done

	else

		log "ERRO" "Não foi encontrado deploy anterior da aplicação $app" && exit 1

	fi
}

# Validar variáveis específicas
test -f $wildfly_dir/bin/jboss-cli.sh || exit 1
test -n $controller_hostname || exit 1
test -n $controller_port || exit 1
test -n $user || exit 1
test -n $password || exit 1

# testar conexão
wildfly_cmd="$wildfly_dir/bin/jboss-cli.sh --connect --controller=$controller_hostname:$controller_port --user=$user --password=$password"
$wildfly_cmd --command="deployment-info --server-group=*" > /dev/null || exit 1

# executar função de deploy ou cópia de logs
case $1 in
	log) copy_log;;
	deploy) deploy_pkg;;
	*) log "ERRO" "O script somente admite os parâmetros 'deploy' ou 'log'.";;
esac