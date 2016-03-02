#!/bin/bash

case "$1" in
    --reconfigure) $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/reconfigure.sh && echo "Reconfigurando serviço..." || exit 1 ;;
    '') echo "Configurando serviço..." ;;
    *)  echo "Argumento inválido" && exit 1 ;;
esac

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

#verify apache params
test -d $apache_confd_dir || exit 1
test -x $apache_init_script || exit 1
id $apache_user > /dev/null || exit 1
groups $apache_user | sed -r "s|$apache_user :||" | grep " $apache_group" > /dev/null || exit 1

#backup vhost_conf
test -f $apache_confd_dir/$apache_vhost_filename && cp -f $apache_confd_dir/$apache_vhost_filename $apache_confd_dir/$apache_vhost_filename.bak

#setup vhost_conf
cp -f $install_dir/template/vhost.template $apache_confd_dir/$apache_vhost_filename || exit 1

sed -i -r "s|@apache_namevirtualhost_directive|$apache_namevirtualhost_directive|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_listen_directive|$apache_listen_directive|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_vhost_name|$apache_vhost_name|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_vhost_port|$apache_vhost_port|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_servername|$apache_servername|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_cgi_alias|$apache_cgi_alias|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@cgi_dir|$cgi_dir|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_log_alias|$apache_log_alias|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@history_dir|$history_dir|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_log_dir|$apache_log_dir|" $apache_confd_dir/$apache_vhost_filename
sed -i -r "s|@apache_vhost_logname|$apache_vhost_logname|" $apache_confd_dir/$apache_vhost_filename

#backup deploy_service
test -f $service_init_script && cp -f $service_init_script $service_init_script.bak

#setup deploy_service
cp -f $install_dir/template/service.template $service_init_script || exit 1

sed -i -r "s|@src_dir|$src_dir|" $service_init_script
sed -i -r "s|@daemon_log|$history_dir/$service_log_file|" $service_init_script

#create directories
mkdir -p $common_work_dir || exit 1
mkdir -p $common_log_dir || exit 1
mkdir -p $history_dir || exit 1
mkdir -p $app_conf_dir || exit 1
mkdir -p $work_dir || exit 1
mkdir -p $log_dir || exit 1
mkdir -p $lock_dir || exit 1

#create deploy_queue
if [ ! -p "$deploy_queue" ]; then
    mkfifo "$deploy_queue" || exit 1
fi

#setup owner/permissions
chmod 775 $common_work_dir || exit 1
chmod 775 $common_log_dir || exit 1
chmod 755 $src_dir/common/sh/query_file.sh || exit 1
chmod 755 $service_init_script || exit 1
chmod 770 $deploy_queue || exit 1
chmod 775 $history_dir || exit 1
chmod 775 $app_conf_dir || exit 1
chmod 775 $work_dir || exit 1
chmod 775 $log_dir || exit 1
chmod 775 $lock_dir || exit 1
chmod 755 $src_dir/server/cgi/* || exit 1

chgrp $apache_group $common_work_dir || exit 1
chgrp $apache_group $common_log_dir || exit 1
chgrp $apache_group $src_dir/common/sh/query_file.sh || exit 1
chgrp $apache_group $service_init_script || exit 1
chgrp $apache_group $deploy_queue
chgrp -R $apache_group $history_dir || exit 1
chgrp -R $apache_group $app_conf_dir || exit 1
chgrp -R $apache_group $work_dir || exit 1
chgrp -R $apache_group $log_dir || exit 1
chgrp -R $apache_group $lock_dir || exit 1
chgrp -R $apache_group $src_dir/server/cgi || exit 1

#restart services
$apache_init_script restart || exit 1
$service_init_script restart || exit 1

echo "Instalação concluída."
exit 0
