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
# PREPARAR timezone
#
##################################################################
# Workaround para el Timezone, en vez de montar el fichero en modo read-only:
# 1) En el DOCKERFILE
#    RUN mkdir -p /config/tz && mv /etc/timezone /config/tz/ && ln -s /config/tz/timezone /etc/
# 2) En el Script entrypoint:
if [ -d '/config/tz' ]; then
    dpkg-reconfigure -f noninteractive tzdata
    echo "Hora actual: `date`"
fi
# 3) Al arrancar el contenedor, montar el volumen, a contiuación un ejemplo:
#     /Apps/data/tz:/config/tz
# 4) Localizar la configuración:
#     echo "Europe/Madrid" > /Apps/data/tz/timezone

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
	
	##################################################################
	#
	# FICHEROS DE CONFIGURACIÓN DE Courier-Imap
	#
	# Utilizo ficheros externos desde el directorio de datos persistentes
	# En caso de no existir crearé una primera configuración válida. 
	#
	# Utilizo la técnica de enlaces simbólicos (parecida a la de timezone)
	# debido a que el montaje de ficheros no funcionaba con docker 1.6.1.
	#
	# Afecta a cuatro ficheros de configuración.
	#
	# /etc/courier/imapd
	# /etc/courier/authdaemonrc
	# /etc/courier/imapd-ssl
	# /etc/courier/authmysqlrc
	# /etc/courier/imapd.cnf
	#
	#
	# 1) En el DOCKERFILE
	#    RUN mkdir -p /config/courierimap 
	#    RUN touch /config/courierimap/imapd && ln -s /config/courierimap/imapd /etc/courier/
	#    RUN touch /config/courierimap/authdaemonrc && ln -s /config/courierimap/authdaemonrc /etc/courier/
	#    RUN touch /config/courierimap/imapd-ssl && ln -s /config/courierimap/imapd-ssl /etc/courier/
	#    RUN touch /config/courierimap/authmysqlrc && ln -s /config/courierimap/authmysqlrc /etc/courier/
	#    RUN touch /config/courierimap/imapd.cnf && ln -s /config/courierimap/imapd.cnf /etc/courier/
	#
	# 2) En el Script entrypoint:
	#    if [ -d '/config/courierimap' ]; then
	#        #
	#        # Comprobar si existe cada uno de los cuatro ficheros y crearlos en caso contrario...
	#        # 
	#    fi
	#
	# 3) Al arrancar el contenedor, montar el volumen, a contiuación un ejemplo:
	#     /Apps/data/correo/courierimap:/config/courierimap
	#
	# 4) Modificar la configuración: 
	#     4.1.- Arrancar el contenedor una vez para que se creen los ficheros
	#     4.2.- Parar el contenedor
	#     4.3.- Modificar los ficheros y volver a arrancar el contenedor
	#

	
	# 2) En el Script entrypoint:
	if [ -d '/config/courierimap' ]; then
        #
        # Comprobar si existe cada uno de los cuatro ficheros y crearlos en caso contrario...
        # 

		############
		#
		# /etc/courier/imapd
		#
		############
	
		#sed -i "s/^MAXDAEMONS=.*/MAXDAEMONS=60/g" /etc/courier/imapd
	    #sed -i "s/^MAXPERIP=.*/MAXPERIP=100/g" /etc/courier/imapd
   		#sed -i "s/^IMAP_TRASHFOLDERNAME=.*/IMAP_TRASHFOLDERNAME=\"Deleted Messages\"/g" /etc/courier/imapd
    	#sed -i "s/^IMAP_EMPTYTRASH=.*/IMAP_EMPTYTRASH=\"Deleted Messages\":7/g" /etc/courier/imapd
    	#sed -i "s/^MAILDIRPATH=.*/MAILDIRPATH=Maildir/g" /etc/courier/imapd

		### 
		### INICIO FICHERO /etc/courier/imapd
		### ------------------------------------------------------------------------------------------------
		
		if [[ ! -s /etc/courier/imapd ]]; then
		
			echo "Creo el fichero /etc/courier/imapd !!"

			cat > /etc/courier/imapd <<-EOF_IMAPD
	
			ADDRESS=0
			PORT=143
			MAXDAEMONS=60
			MAXPERIP=100
			PIDFILE=/var/run/courier/imapd.pid
			TCPDOPTS="-nodnslookup -noidentlookup"
			LOGGEROPTS="-name=imapd"
			IMAP_CAPABILITY="IMAP4rev1 UIDPLUS CHILDREN NAMESPACE THREAD=ORDEREDSUBJECT THREAD=REFERENCES SORT QUOTA IDLE"
			IMAP_KEYWORDS=1
			IMAP_ACL=1
			IMAP_CAPABILITY_ORIG="IMAP4rev1 UIDPLUS CHILDREN NAMESPACE THREAD=ORDEREDSUBJECT THREAD=REFERENCES SORT QUOTA AUTH=CRAM-MD5 AUTH=CRAM-SHA1 AUTH=CRAM-SHA256 IDLE"
			IMAP_PROXY=0
			IMAP_PROXY_FOREIGN=0
			IMAP_IDLE_TIMEOUT=30
			IMAP_MAILBOX_SANITY_CHECK=1
			IMAP_CAPABILITY_TLS="\$IMAP_CAPABILITY AUTH=PLAIN"
			IMAP_CAPABILITY_TLS_ORIG="\$IMAP_CAPABILITY_ORIG AUTH=PLAIN"
			IMAP_DISABLETHREADSORT=0
			IMAP_CHECK_ALL_FOLDERS=0
			IMAP_OBSOLETE_CLIENT=0
			IMAP_UMASK=022
			IMAP_ULIMITD=131072
			IMAP_USELOCKS=1
			IMAP_SHAREDINDEXFILE=/etc/courier/shared/index
			IMAP_ENHANCEDIDLE=0
			IMAP_TRASHFOLDERNAME="Deleted Messages"
			IMAP_EMPTYTRASH="Deleted Messages":7
			IMAP_MOVE_EXPUNGE_TO_TRASH=0
			SENDMAIL=/usr/sbin/sendmail
			HEADERFROM=X-IMAP-Sender
			IMAPDSTART=YES
			MAILDIRPATH=Maildir
	
			EOF_IMAPD

		fi
		### ------------------------------------------------------------------------------------------------
		### FIN FICHERO /etc/courier/imapd
		### 
		

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
		
		if [[ ! -s /etc/courier/authdaemonrc ]]; then

			echo "Creo el fichero /etc/courier/authdaemonrc !!"

			cat > /etc/courier/authdaemonrc <<-EOF_AUTHDAEMON
	
			authmodulelist="authmysql"
			daemons=5
			authdaemonvar=/var/run/courier/authdaemon
			DEBUG_LOGIN=2
			DEFAULTOPTIONS=""
			LOGGEROPTS="-name=courier-imap"
	
			EOF_AUTHDAEMON
			
		fi
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
		#  IMAPDSTARTTLS controla si courier-imapd (puerto 143) anuncia que soporta STARTTLS. 
		#  El cliente IMAP realizará una conexión regular no encriptada por el puerto 143 y
		#  al ver que el cliente soporta STARTTLS podrá conmutar a modo encriptado por el 
		#  mismo puerto 143 antes de hacer el login
		#
		#  En mi caso "deshabilito" SSL2 y SSL3, bajo ninguna circunstancia deberían habilitarse,
		#  ambos están o rotos o con vulnerabilidades graves. 
		#  Fuente: https://owasp.org/index.php/Transport_Layer_Protection_Cheat_Sheet
		#
		#  IMAP_TLS_REQUIRED=[1|0] controla si queremos forzar TLS. Si es igual a 1 entonces
		#  se exige que se ejecute STARTTLS antes de login, si está a 0 el cliente podrá 
		#  hacer login por el puerto 143 sin TLS o bien podrá hacer primero el TLS y luego login.
		#
		#  Mejor práctica: Ofrecer "solo" los protocolos TLS: TLS1.0, TLS 1.1 o TLS 1.2.
		#

		### 
		### INICIO FICHERO /etc/courier/imapd-ssl
		### ------------------------------------------------------------------------------------------------
		
		if [[ ! -s /etc/courier/imapd-ssl ]]; then

			echo "Creo el fichero /etc/courier/imapd-ssl !!"

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
		fi
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
		
		if [[ ! -s /etc/courier/authmysqlrc ]]; then

			echo "Creo el fichero /etc/courier/authmysqlrc !!"

			cat > /etc/courier/authmysqlrc <<-EOF_AUTHMYSQL
	
			MYSQL_SERVER		${mysqlHost}
			MYSQL_USERNAME		${MAIL_DB_USER}
			MYSQL_PASSWORD		${MAIL_DB_PASS}
			MYSQL_PORT			${mysqlPort}
			MYSQL_OPT			0
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
		
		fi
		### ------------------------------------------------------------------------------------------------
		### FIN FICHERO /etc/courier/authmysqlrc  
		### 


		############
		#
		# /etc/courier/imapd.cnf
		#
		############
		#
		# Este fichero se utiliza para crear tus propios certificados. 
		
		### 
		### INICIO FICHERO /etc/courier/imapd.cnf
		### ------------------------------------------------------------------------------------------------
		
		if [[ ! -s /etc/courier/imapd.cnf ]]; then

			echo "Creo el fichero /etc/courier/imapd.cnf !!"

			cat > /etc/courier/imapd.cnf <<-EOF_IMAPDCNF
	
			RANDFILE = /etc/courier/imapd.rand
			
			[ req ]
			default_bits = 4096
			encrypt_key = yes
			distinguished_name = req_dn
			x509_extensions = cert_type
			prompt = no
			default_md = sha1
			
			[ req_dn ]
			C=ES
			ST=Madrid
			L=Mi querido pueblo
			O=Org
			OU=Clave SSL IMAP
			CN=localhost
			emailAddress=postmaster@tld.org

			[ cert_type ]
			nsCertType = server
			
			EOF_IMAPDCNF
		
			cd /etc/courier
			rm -f imapd.pem
			mkimapdcert

			#
			# ToDo !!!.. De momento no regenero los certificados si se modifica el 
			# fichero impad.pem externamente... ToDo !!!!
			#

		fi
		### ------------------------------------------------------------------------------------------------
		### FIN FICHERO /etc/courier/imapd.cnf  
		### 

	fi


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
	chown -R vmail:vmail /data/vmail &

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
