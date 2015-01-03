#
# "courier-imap" base by Luispa, Dec 2014
# 
# Servidor de correo IMAP con courier-imap
#
# -----------------------------------------------------

#
# Desde donde parto...
#
FROM debian:jessie

# Autor de este Dockerfile
#
MAINTAINER Luis Palacios <luis@luispa.com>

# Pido que el frontend de Debian no sea interactivo
ENV DEBIAN_FRONTEND noninteractive

# Actualizo el sistema operativo e instalo lo mínimo
#
RUN apt-get update && \
    apt-get -y install 	locales \
    					net-tools \
                       	vim \
                       	supervisor \
                       	wget \
                       	curl \
                        rsyslog

# Preparo locales y Timezone
#
RUN locale-gen es_ES.UTF-8
RUN locale-gen en_US.UTF-8
RUN dpkg-reconfigure locales
RUN echo "Europe/Madrid" > /etc/timezone; dpkg-reconfigure -f noninteractive tzdata

# HOME
ENV HOME /root

# ------- ------- ------- ------- ------- ------- -------
# DEBUG ( Descomentar durante debug del contenedor )
# ------- ------- ------- ------- ------- ------- -------
#
# Herramientas SSH, tcpdump y net-tools
RUN apt-get update && \
    apt-get -y install 	openssh-server \
                       	tcpdump \
                        net-tools
# Setup de SSHD                                                
RUN mkdir /var/run/sshd
RUN echo 'root:rootdocker' | chpasswd
RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile
# Script que uso a menudo durante debug
RUN echo "grep -vh '^[[:space:]]*#' \"\$@\" | grep -v '^//' | grep -v '^;' | grep -v '^\$' | grep -v '^\!' | grep -v '^--'" > /usr/bin/confcat
RUN chmod 755 /usr/bin/confcat

# ------- ------- ------- ------- ------- ------- -------
# Instalo courier-imap
# ------- ------- ------- ------- ------- ------- -------
#
# Instalo los paquetes básicos
#
# Necesario para que instale courier-authlib-mysql
RUN mkdir -p /var/run/courier/authdaemon
RUN > /var/run/courier/authdaemon/pid.lock   
RUN chown -R daemon:daemon /var/run/courier
# Instalación de courier-imap
RUN apt-get update && \
    apt-get -y install 	courier-imap \
    				 	courier-imap-ssl \
    				 	courier-authlib-mysql
RUN rm -fr /var/run/courier

# SSL
ADD imapd.cnf /etc/courier/imapd.cnf
WORKDIR /etc/courier
RUN rm imapd.pem
RUN mkimapdcert

# Puertos por el que escucha el servidor
#
EXPOSE 143
#EXPOSE 25143
EXPOSE 993

#-----------------------------------------------------------------------------------

# Ejecutar siempre al arrancar el contenedor este script
#
ADD do.sh /do.sh
RUN chmod +x /do.sh
ENTRYPOINT ["/do.sh"]

#
# Si no se especifica nada se ejecutará lo siguiente: 
#
CMD ["/usr/bin/supervisord", "-n -c /etc/supervisor/supervisord.conf"]
