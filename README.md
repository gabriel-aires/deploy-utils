# BashTable (formerly known as deploy-utils)

## Description:

Platform for app deployment automation and information retrieval written in shell script.

## Dependencies:

These are the system requirements for the RHEL/CentOS 6 distribution:

**Package**|**Version**
----------|----------
bash      |     4.1.2
dos2unix  |       3.1
unix2dos  |       2.2
coreutils |       8.4
findutils |     4.4.2
cifs-utils|     4.8.1
nfs-utils |     1.2.3
samba     |    3.6.23
git       |     1.7.1
rsync     |     3.0.6
grep      |      2.20
sed       |     4.2.1
perl      |    5.10.1
httpd     |    2.2.15

## Server Setup:

Run the following commands as root for the initial setup:

### System Update
```
yum update bash dos2unix unix2dos coreutils findutils cifs-utils nfs-utils samba git rsync grep sed perl httpd -y
```

### Deployment Server Installation
```
cd /opt
git clone https://github.com/gabriel-aires/BashTable.git
/opt/BashTable/src/server/sh/setup.sh --reconfigure
chkconfig --add deploy_server
chkconfig deploy_server on
```

### SSL/TLS Configuration (optional)
```
service deploy_server stop
yum install mod_ssl openssl
openssl genrsa -out ca.key 2048
openssl req -new -key ca.key -out ca.csr
openssl x509 -req -days 365 -in ca.csr -signkey ca.key -out ca.crt
cp ca.crt /etc/pki/tls/certs
cp ca.key /etc/pki/tls/private/ca.key
cp ca.csr /etc/pki/tls/private/ca.csr
vim /opt/BashTable/src/server/conf/global.conf  #update parameters ssl_enable, ssl_crt_path, ssl_key_path and apache_vhost_port
/opt/BashTable/src/server/sh/setup.sh
```

### Shared Directories Setup
```
service nfs stop
chkconfig nfs on
echo /opt/BashTable/src/server/conf/agents >> /etc/exports
echo /var/lock/BashTable >> /etc/exports
echo /opt/BashTable/src/server/log/ >> /etc/exports
echo /opt/BashTable/src/server/upload/ >> /etc/exports
vim /etc/exports # edit entries as following: /var/lock/BashTable $host01(rw,no_root_squash) $host02(rw,no_root_squash) ...
service nfs restart
```

## Agents Setup:

The following steps must be applied to all the machines where automated log retrieval and package deployment are desired:

### System Update
```
yum update bash dos2unix unix2dos coreutils findutils cifs-utils nfs-utils samba git rsync grep sed perl -y
```

### Mount NFS Shares (previously exported from the deployment server)
```
cd /mnt
mkdir deploy_upload deploy_lock deploy_log deploy_conf
mount -t nfs $deployment_server:/opt/BashTable/src/server/conf/agents deploy_conf
mount -t nfs $deployment_server:/opt/BashTable/src/server/log deploy_log
mount -t nfs $deployment_server:/opt/BashTable/src/server/upload deploy_upload
mount -t nfs $deployment_server:/var/lock/BashTable deploy_lock
```

### Agent Installation
```
cd /opt
git clone https://github.com/gabriel-aires/BashTable.git
/opt/BashTable/src/agents/sh/setup.sh --reconfigure
chkconfig --add deploy_agent
chkconfig deploy_agent on
```

### Observation

This system is being reworked under the following project https://github.com/gabriel-aires/odin, originally intended to be a complete TCL rewrite of BashTables. Both platforms shall be independently maintained for the foreseeable future.

## Author:

Gabriel Aires Guedes - airesgabriel@gmail.com

Last updated at 2018-05-16.
