ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache rsync

COPY run.sh /
WORKDIR /data
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
