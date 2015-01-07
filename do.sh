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
	
	echo "Configuro imapd"
	
	############
	#
	# /etc/courier/imapd
	#
	############
	
	sed -i "s/^MAXDAEMONS=.*/MAXDAEMONS=60/g" /etc/courier/imapd
    sed -i "s/^MAXPERIP=.*/MAXPERIP=100/g" /etc/courier/imapd
    sed -i "s/^IMAP_TRASHFOLDERNAME=.*/IMAP_TRASHFOLDERNAME=\"Deleted Messages\"/g" /etc/courier/imapd
    sed -i "s/^IMAP_EMPTYTRASH=.*/IMAP_EMPTYTRASH=\"Deleted Messages\":7/g" /etc/courier/imapd
    sed -i "s/^MAILDIRPATH=.*/MAILDIRPATH=Maildir/g" /etc/courier/imapd



	############
	#
	# /etc/courier/authdaemonrc
	#
	############
	#
	# Responsable de configuración de la librería de autenticación de Courier-Imap. 
	# La configuro de manera que "solo" compruebe el usuario/contraseña usando SQL
	
	### 
	### INICIO FICHERO  /etc/courier/authdaemonrc
	### ------------------------------------------------------------------------------------------------
	cat > /etc/courier/authdaemonrc <<-EOF_AUTHDAEMON
	
	authmodulelist="authmysql"
	daemons=5
	authdaemonvar=/var/run/courier/authdaemon
	DEBUG_LOGIN=2
	DEFAULTOPTIONS=""
	LOGGEROPTS="-name=courier-imap"
	
	EOF_AUTHDAEMON
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO  /etc/courier/authdaemonrc
	### 



	############
	#
	# /etc/courier/imapd-ssl
	#
	############
	#
	#
	#
	# Hay dos tipos de conexiones encriptadas. La única diferencia 
	# está en cómo se arrancan: 
	#
	#  IMAPDSSLSTART controla si courier-imapd-ssl arranca y escucha en el puerto 993
	#  Será una conexión completamente encriptada, de principio a fin
	#
	#  IMAPDSTARTTLS controls si courier-imapd (puerto 443) anuncia que soporta STARTTLS. 
	#  El cliente IMAP realizará una conexión regular no encriptada por el puerto 443 y
	#  al ver que el cliente soporta STARTTLS podrá conmutar a modo encriptado por el 
	#  mismo puerto 143 antes de hacer el login
	#
	#  En mi caso "deshabilito" SSL2 y SSL3, bajo ninguna circunstancia deberían habilitarse,
	#  ambos están o rotos o con vulnerabilidades graves. 
	#    Fuente: https://owasp.org/index.php/Transport_Layer_Protection_Cheat_Sheet
	#
	#  Mejor práctica: Ofrecer "solo" los protocolos TLS: TLS1.0, TLS 1.1 o TLS 1.2.
	#

	### 
	### INICIO FICHERO /etc/courier/imapd-ssl
	### ------------------------------------------------------------------------------------------------
	cat > /etc/courier/imapd-ssl <<-EOF_IMAPDSSL
	
	SSLPORT=993
	SSLADDRESS=0
	SSLPIDFILE=/var/run/courier/imapd-ssl.pid
	SSLLOGGEROPTS="-name=imapd-ssl"
	IMAPDSSLSTART=NO
	IMAPDSTARTTLS=YES
	IMAP_TLS_REQUIRED=1
	COURIERTLS=/usr/bin/couriertls
	TLS_PROTOCOL=TLS1
	TLS_STARTTLS_PROTOCOL=TLS1
	TLS_CERTFILE=/etc/courier/imapd.pem
	TLS_DHPARAMS=/etc/courier/dhparams.pem
	TLS_TRUSTCERTS=/etc/ssl/certs
	TLS_VERIFYPEER=NONE
	TLS_CACHEFILE=/var/lib/courier/couriersslcache
	TLS_CACHESIZE=524288
	MAILDIRPATH=Maildir
	
	EOF_IMAPDSSL
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/courier/imapd-ssl
	### 



	############
	#
	# /etc/courier/authmysqlrc
	#
	############
	#
	# En mi base de datos tengo las contraseñas en clear text, así que elimino la línea
	# "MYSQL_CRYPT_PWFIELD" del fichero authmysqlrc. 
	# NOTA: Investigar en el futuro como migrar a contraseñas encriptadas y activar
	# MYSQL_CRYPT_PWFIELD	password
	
	### 
	### INICIO FICHERO /etc/courier/authmysqlrc
	### ------------------------------------------------------------------------------------------------
	cat > /etc/courier/authmysqlrc <<-EOF_AUTHMYSQL
	
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
	
	EOF_AUTHMYSQL
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/rsyslog.conf  
	### 



	############
	#
	# rsyslogd
	#
	############
	# Configurar rsyslogd para que envíe logs a un agregador remoto
	echo "Configuro rsyslog.conf"

	### 
	### INICIO FICHERO /etc/rsyslog.conf 
	### ------------------------------------------------------------------------------------------------
    cat > /etc/rsyslog.conf <<-EOF_RSYSLOG
	
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
	
	EOF_RSYSLOG
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/rsyslog.conf  
	### 



	############
	#
	# Supervisor
	# 
	############
	echo "Configuro supervisord.conf"

	### 
	### INICIO FICHERO /etc/supervisor/conf.d/supervisord.conf  
	### ------------------------------------------------------------------------------------------------
	cat > /etc/supervisor/conf.d/supervisord.conf <<-EOF_SUPERVISOR
	
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
	
	EOF_SUPERVISOR
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/supervisor/conf.d/supervisord.conf  
	### 
	
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
