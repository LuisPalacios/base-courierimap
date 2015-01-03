# Introducción

Este repositorio alberga un *contenedor Docker* para montar un servidor courier-imap. Lo encontrarás automatizado en el Registry Hub de Docker [luispa/base-couriermap](https://registry.hub.docker.com/u/luispa/base-couriermap/) conectado con el proyecto GitHub [base-couriermap](https://github.com/LuisPalacios/base-couriermap). 

Te recomiendo que eches un vistazo al proyecto [servicio-correo](https://github.com/LuisPalacios/servicio-correo) como ejemplo de uso.



## Ficheros

* **Dockerfile**: Para crear la base de servicio.
* **do.sh**: Para arrancar el contenedor creado con esta imagen.

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

    docker run --rm -t -i -p 143:143 -p 993:993 -e FLUENTD_LINK=fluentd.tld.org.org:24224  -e MAIL_DB_USER=correo -e MAIL_DB_PASS=correopass -e MAIL_DB_NAME=correodb -e MYSQL_LINK="mysqlcorreo.tld.org:33000" -v /Apps/data/correo/vmail:/data/vmail luispa/base-courierimap /bin/bash

