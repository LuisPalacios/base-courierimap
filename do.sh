#!/bin/bash
#
# Punto de entrada para el servicio courier-imap
#
# Activar el debug de este script:
# set -eux

##################################################################
#
# main
#
##################################################################

# Averiguar si necesito configurar por primera vez
#
CONFIG_DONE="/.config_courierimap_done"
NECESITA_PRIMER_CONFIG="si"
if [ -f ${CONFIG_DONE} ] ; then
    NECESITA_PRIMER_CONFIG="no"
fi

##################################################################
#
# VARIABLES OBLIGATORIAS
#
##################################################################

## Servidor:Puerto por el que conectar con el servidor MYSQL
#
if [ -z "${MYSQL_LINK}" ]; then
	echo >&2 "error: falta el Servidor:Puerto del servidor MYSQL: MYSQL_LINK"
	exit 1
fi
mysqlHost=${MYSQL_LINK%%:*}
mysqlPort=${MYSQL_LINK##*:}


## Variables para acceder a la BD de PostfixAdmin donde están
#  todos los usuarios, contraseñas, dominios, etc...
#
if [ -z "${MAIL_DB_USER}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_USER"
	exit 1
fi
if [ -z "${MAIL_DB_PASS}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_PASS"
	exit 1
fi
if [ -z "${MAIL_DB_NAME}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_NAME"
	exit 1
fi

## Servidor:Puerto por el que escucha el agregador de Logs (fluentd)
#
if [ -z "${FLUENTD_LINK}" ]; then
	echo >&2 "error: falta el Servidor:Puerto por el que escucha fluentd, variable: FLUENTD_LINK"
	exit 1
fi
fluentdHost=${FLUENTD_LINK%%:*}
fluentdPort=${FLUENTD_LINK##*:}

##################################################################
#
# Usuario/Grupo "vmail" - owner directorio donde residen los mails 
# recibidos vía el contendor postfix o leídos desde el contenedor
# courier-imap. 
#
# En ambos contenedores (postfix y courier-imap) debo montar el 
# directorio externo persistente elegido para dejar los mails. 
#
# run: -v /Apps/data/vmail:/data/vmail
#
# Además debo tener el mismo usuario como propietario de dicha 
# estructura de directorios, así que en ambos contenedores de 
# postfix y courier-imap creo el usuario vmail con mismo UID/GID
#
##################################################################
ret=false
getent passwd $1 >/dev/null 2>&1 && ret=true
if $ret; then
    echo ""
else
	groupadd -g 3008 vmail
	useradd -u 3001 -g vmail -M -d /data/vmail -s /bin/false vmail
fi

##################################################################
#
# PREPARAR EL CONTAINER POR PRIMERA VEZ
#
##################################################################

# Necesito configurar por primera vez?
#
if [ ${NECESITA_PRIMER_CONFIG} = "si" ] ; then
	
	echo "Realizo la configuración por primera vez"
	
	############
	#
	# /etc/courier/imapd
	#
	############
	echo "Configuro clamd.conf"

	sed -i "s/^MAXDAEMONS=.*/MAXDAEMONS=60/g" /etc/courier/imapd
    sed -i "s/^MAXPERIP=.*/MAXPERIP=100/g" /etc/courier/imapd
    sed -i "s/^IMAP_TRASHFOLDERNAME=.*/IMAP_TRASHFOLDERNAME=\"Deleted Messages\"/g" /etc/courier/imapd
    sed -i "s/^IMAP_EMPTYTRASH=.*/IMAP_EMPTYTRASH=\"Deleted Messages\":7/g" /etc/courier/imapd
    sed -i "s/^MAILDIRPATH=.*/MAILDIRPATH=Maildir/g" /etc/courier/imapd

#authmodulelistorig="authuserdb authpam authpgsql authldap authmysql authcustom authpipe"

	cat > /etc/courier/authdaemonrc <<EOFAUTHDAEMON

authmodulelist="authmysql"
daemons=5
authdaemonvar=/var/run/courier/authdaemon
DEBUG_LOGIN=2
DEFAULTOPTIONS=""
LOGGEROPTS="-name=courier-imap"

EOFAUTHDAEMON

# En mi base de datos tengo las contraseñas en clear text, así que elimino la línea
# siguiente del fichero authmysqlrc. NOTA: Investigar en el futuro poner crypted en todo!!
#MYSQL_CRYPT_PWFIELD	password

	cat > /etc/courier/authmysqlrc <<EOFAUTHMYSQL
	
MYSQL_SERVER		${mysqlHost}
MYSQL_USERNAME		${MAIL_DB_USER}
MYSQL_PASSWORD		${MAIL_DB_PASS}
MYSQL_PORT		${mysqlPort}
MYSQL_OPT		0
MYSQL_DATABASE		${MAIL_DB_NAME}
MYSQL_USER_TABLE	mailbox
MYSQL_CLEAR_PWFIELD	password
MYSQL_UID_FIELD		'3001'
MYSQL_GID_FIELD		'3008'
MYSQL_LOGIN_FIELD	username
MYSQL_HOME_FIELD	'/data/vmail'
MYSQL_NAME_FIELD	name
MYSQL_MAILDIR_FIELD	maildir

EOFAUTHMYSQL


	############
	#
	# rsyslogd
	#
	############
	# Configurar rsyslogd para que envíe logs a un agregador remoto
	echo "Configuro rsyslog.conf"

    cat > /etc/rsyslog.conf <<EOFRSYSLOG
\$LocalHostName courier-imap
\$ModLoad imuxsock # provides support for local system logging
#\$ModLoad imklog   # provides kernel logging support
#\$ModLoad immark  # provides --MARK-- message capability

# provides UDP syslog reception
#\$ModLoad imudp
#\$UDPServerRun 514

# provides TCP syslog reception
#\$ModLoad imtcp
#\$InputTCPServerRun 514

# Activar para debug interactivo
#
#\$DebugFile /var/log/rsyslogdebug.log
#\$DebugLevel 2

\$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat

\$FileOwner root
\$FileGroup adm
\$FileCreateMode 0640
\$DirCreateMode 0755
\$Umask 0022

#\$WorkDirectory /var/spool/rsyslog
#\$IncludeConfig /etc/rsyslog.d/*.conf

# Dirección del Host:Puerto agregador de Log's con Fluentd
#
*.* @@${fluentdHost}:${fluentdPort}

# Activar para debug interactivo
#
# *.* /var/log/syslog

EOFRSYSLOG

	############
	#
	# Supervisor
	# 
	############
	echo "Configuro supervisord.conf"

	cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[unix_http_server]
file=/var/run/supervisor.sock 					; path to your socket file

[inet_http_server]
port = 0.0.0.0:9001								; allow to connect from web browser to supervisord

[supervisord]
logfile=/var/log/supervisor/supervisord.log 	; supervisord log file
logfile_maxbytes=50MB 							; maximum size of logfile before rotation
logfile_backups=10 								; number of backed up logfiles
loglevel=error 									; info, debug, warn, trace
pidfile=/var/run/supervisord.pid 				; pidfile location
minfds=1024 									; number of startup file descriptors
minprocs=200 									; number of process descriptors
user=root 										; default user
childlogdir=/var/log/supervisor/ 				; where child log files will live

nodaemon=false 									; run supervisord as a daemon when debugging
;nodaemon=true 									; run supervisord interactively (production)
 
[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
 
[supervisorctl]
serverurl=unix:///var/run/supervisor.sock		; use a unix:// URL for a unix socket 

[program:authdaemon]
process_name = authdaemon
command=/etc/init.d/courier-authdaemon start
startsecs = 0
autorestart = false

[program:imap]
process_name = imap
command=/etc/init.d/courier-imap start
startsecs = 0
autorestart = false

[program:imapssl]
process_name = imapssl
command=/etc/init.d/courier-imap-ssl start
startsecs = 0
autorestart = false

[program:rsyslog]
process_name = rsyslogd
command=/usr/sbin/rsyslogd -n
startsecs = 0
autorestart = true

#
# DESCOMENTAR PARA DEBUG o SI QUIERES SSHD
#
#[program:sshd]
#process_name = sshd
#command=/usr/sbin/sshd -D
#startsecs = 0
#autorestart = true

EOF

	# Re-Confirmo los permisos de /data/vmail
	chown -R vmail:vmail /data/vmail

    #
    # Creo el fichero de control para que el resto de 
    # ejecuciones no realice la primera configuración
    > ${CONFIG_DONE}
	echo "Termino la primera configuración del contenedor"
	
fi

##################################################################
#
# EJECUCIÓN DEL COMANDO SOLICITADO
#
##################################################################
#
exec "$@"
