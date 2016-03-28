#!/bin/bash

interactive='false'
verbosity='verbose'

function end() {

    if [ "$1" != '0' ]; then
        echo "ERRO. Instalação interrompida."
    fi

    exit $1

}

case "$1" in
    --reconfigure)
        echo "Reconfigurando serviço..."
        $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/reconfigure.sh || end 1
        ;;
    '') echo "Configurando serviço..."
        ;;
    *)  echo "Argumento inválido" && end 1
        ;;
esac

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || end 1
source $install_dir/sh/include.sh || end 1

valid "ssl_enable" "regex_bool" "\nErro. A variável ssl_enable é booleana (true/false)."
valid "set_apache_listen_directive" "regex_bool" "\nErro. A variável set_apache_listen_directive é booleana (true/false)."
valid "set_apache_namevirtualhost_directive" "regex_bool" "\nErro. A variável set_apache_namevirtualhost_directive é booleana (true/false)."

#verify apache params
test -d "$apache_confd_dir" || end 1
test -n "$apache_init_script" || end 1
id "$apache_user" > /dev/null || end 1
groups "$apache_user" | sed -r "s|$apache_user :||" | grep " $apache_group" > /dev/null || end 1

#backup vhost_conf
test -f $apache_confd_dir/$apache_vhost_filename && cp -f $apache_confd_dir/$apache_vhost_filename $apache_confd_dir/$apache_vhost_filename.bak

#setup vhost_conf
$ssl_enable && vhost_template=$install_dir/template/vhost_ssl.template || vhost_template=$install_dir/template/vhost.template
$set_apache_namevirtualhost_directive && apache_namevirtualhost_directive="NameVirtualHost $apache_vhost_name:$apache_vhost_port" || apache_namevirtualhost_directive=''
$set_apache_listen_directive && apache_listen_directive="Listen $apache_vhost_port" || apache_listen_directive=''

cp -f $vhost_template $apache_confd_dir/$apache_vhost_filename || end 1
test -w $vhost_template || end 1

sed -i -r "s|@apache_cgi_alias|$apache_cgi_alias|g" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_log_alias|$apache_log_alias|g" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_css_alias|$apache_css_alias|g" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@ssl_crt_path|$ssl_crt_path|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@ssl_key_path|$ssl_key_path|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_namevirtualhost_directive|$apache_namevirtualhost_directive|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_listen_directive|$apache_listen_directive|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_vhost_name|$apache_vhost_name|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_vhost_port|$apache_vhost_port|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_servername|$apache_servername|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@cgi_dir|$cgi_dir|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@cgi_timeout|$cgi_timeout|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@css_dir|$css_dir|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@history_dir|$history_dir|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_log_dir|$apache_log_dir|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_vhost_logname|$apache_vhost_logname|" $apache_confd_dir/$apache_vhost_filename

#setup apache_authentication
touch $web_users_file || end 1
touch $web_groups_file || end 1
touch $web_permissions_file || end 1

htpasswd -b "$web_users_file" "$web_admin_user" "$web_admin_password" || end 1

if grep -Ex "admin:.*" "$web_groups_file" > /dev/null; then
    grep -Ex "admin:.* $web_admin_user ?.*" "$web_groups_file" > /dev/null || sed -i -r "s|^(admin:.*)$|\1 $web_admin_user|" "$web_groups_file"
else
    echo "admin: $web_admin_user" >> "$web_groups_file"
fi

test -f $cgi_dir/.htaccess && cp -f $cgi_dir/.htaccess $cgi_dir/.htaccess.bak
cp -f $install_dir/template/htaccess.template $cgi_dir/.htaccess

cgi_private_regex="^$(echo "$cgi_private_pages" | sed -r 's/^( +)?(.)/\(\2/g' | sed -r 's/(.)( +)?$/\1\)/g' | sed -r "s/ +/|/g")\.cgi$"
cgi_admin_regex="^$(echo "$cgi_admin_pages" | sed -r 's/^( +)?(.)/\(\2/g' | sed -r 's/(.)( +)?$/\1\)/g' | sed -r "s/ +/|/g")\.cgi$"

sed -i -r "s|@web_users_file|$web_users_file|" $cgi_dir/.htaccess
sed -i -r "s|@web_groups_file|$web_groups_file|" $cgi_dir/.htaccess
sed -i -r "s/@cgi_private_regex/$cgi_private_regex/" $cgi_dir/.htaccess
sed -i -r "s/@cgi_admin_regex/$cgi_admin_regex/" $cgi_dir/.htaccess

#backup deploy_service
test -f $service_init_script && cp -f $service_init_script $service_init_script.bak

#setup deploy_service
cp -f $install_dir/template/service.template $service_init_script || end 1
test -w $service_init_script || end 1

sed -i -r "s|@src_dir|$src_dir|" $service_init_script
sed -i -r "s|@daemon_log|$history_dir/$service_log_file|" $service_init_script

#create directories
mkdir -p $common_work_dir || end 1
mkdir -p $common_log_dir || end 1
mkdir -p $history_dir || end 1
mkdir -p $app_conf_dir || end 1
mkdir -p $agent_conf_dir || end 1
mkdir -p $work_dir || end 1
mkdir -p $upload_dir || end 1
mkdir -p $log_dir || end 1
mkdir -p $lock_dir || end 1

#create deploy_queue
if [ ! -p "$deploy_queue" ]; then
    mkfifo "$deploy_queue" || end 1
fi

#setup owner/permissions
chmod 775 $common_work_dir || end 1
chmod 775 $common_log_dir || end 1
chmod 755 $src_dir/common/sh/query_file.sh || end 1
chmod 755 $service_init_script || end 1
chmod 770 $deploy_queue || end 1
chmod 660 $web_users_file || end 1
chmod 660 $web_groups_file || end 1
chmod 660 $web_permissions_file || end 1
chmod 775 $history_dir || end 1
chmod 775 $app_conf_dir || end 1
chmod 775 $agent_conf_dir || end 1
chmod 775 $work_dir || end 1
chmod 775 $upload_dir || end 1
chmod 775 $log_dir || end 1
chmod 775 $lock_dir || end 1
chmod 755 $src_dir/server/cgi/* || end 1
chmod 644 $src_dir/server/css/* || end 1

chgrp $apache_group $common_work_dir || end 1
chgrp $apache_group $common_log_dir || end 1
chgrp $apache_group $src_dir/common/sh/query_file.sh || end 1
chgrp $apache_group $service_init_script || end 1
chgrp $apache_group $deploy_queue || end 1
chgrp $apache_group $web_users_file || end 1
chgrp $apache_group $web_groups_file || end 1
chgrp $apache_group $web_permissions_file || end 1
chgrp -R $apache_group $history_dir || end 1
chgrp -R $apache_group $app_conf_dir || end 1
chgrp -R $apache_group $agent_conf_dir || end 1
chgrp -R $apache_group $work_dir || end 1
chgrp -R $apache_group $upload_dir || end 1
chgrp -R $apache_group $log_dir || end 1
chgrp -R $apache_group $lock_dir || end 1
chgrp -R $apache_group $src_dir/server/cgi || end 1
chgrp -R $apache_group $src_dir/server/css || end 1

#restart services
$apache_init_script restart || end 1
$service_init_script restart || end 1

echo "Instalação concluída."
end 0
