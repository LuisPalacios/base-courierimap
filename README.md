# Introducción

Este repositorio alberga un *contenedor Docker* para montar un servidor courier-imap. Lo encontrarás automatizado en el Registry Hub de Docker [luispa/base-courierimap](https://registry.hub.docker.com/u/luispa/base-courierimap/) conectado con el proyecto GitHub [base-courierimap](https://github.com/LuisPalacios/base-courierimap). 

Tengo otro repositorio [servicio-correo](https://github.com/LuisPalacios/servicio-correo) donde verás un ejemplo de uso. Además te recomiendo que consultes este [apunte técnico sobre varios servicios en contenedores Docker](http://www.luispa.com/?p=172) para tener una visión más global de otros contenedores Docker y fuentes en GitHub y entender mejor este ejemplo.


## Ficheros

* **Dockerfile**: Para crear la base de servicio.
* **do.sh**: Para arrancar el contenedor creado con esta imagen.

# Personalización

### Volumen


Directorio persistente para configurar el Timezone. Crear el directorio /Apps/data/tz y dentro de él crear el fichero timezone. Luego montarlo con -v o con fig.yml

    Montar:
       "/Apps/data/tz:/config/tz"  
    Preparar: 
       $ echo "Europe/Madrid" > /config/tz/timezone

Directorio persistente para los ficheros de configuración. Si los 5 ficheros no existen entonces crearé una primera configuración válida desde "do.sh", usando la técnica de enlaces simbólicos (parecida a la de timezone) debido a que el montaje de ficheros no funcionaba con docker 1.6.1. Afecta a cuatro ficheros de configuración:

    /etc/courier/imapd
    /etc/courier/authdaemonrc
    /etc/courier/imapd-ssl
    /etc/courier/authmysqlrc
    /etc/courier/imapd.cnf


    Montar:
       "/Apps/data/correo/courierimap:/config/courierimap"  

Para modificar los fichero, editarlos directamente en el directorio /config/courieimap tras la primera ejecuación. 
    

## Instalación de la imagen

Para usar la imagen desde el registry de docker hub

    totobo ~ $ docker pull luispa/base-courierimap


## Clonar el repositorio

Si quieres clonar el repositorio lo encontrarás en Github, este es el comando poder trabajar con él directamente

    ~ $ clone https://github.com/LuisPalacios/docker-courierimap.git

Luego puedes crear la imagen localmente con el siguiente comando

    $ docker build -t luispa/base-courierimap ./


## Troubleshooting

A continuación un ejemplo sobre cómo ejecutar manualmente el contenedor, útil para hacer troubleshooting. Ejecuto /bin/bash nada más entrar en el contenedor. 

    docker run --rm -t -i -p 143:143 -p 993:993 -e FLUENTD_LINK=fluentd.tld.org.org:24224  -e MAIL_DB_USER=correo -e MAIL_DB_PASS=correopass -e MAIL_DB_NAME=correodb -e MYSQL_LINK="mysqlcorreo.tld.org:33000" -v /Apps/data/correo/vmail:/data/vmail -v /Apps/data/correo/courierimap:/config/courierimap luispa/base-courierimap /bin/bash

