ARG BUILD_FROM
FROM $BUILD_FROM
COPY run.sh /
WORKDIR /data
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
