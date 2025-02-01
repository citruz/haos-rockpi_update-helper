ARG BUILD_FROM
FROM $BUILD_FROM
COPY run.sh /
WORKDIR /data
RUN chmod a+x /run.sh
RUN mv /run.sh /init

# CMD [ "/run.sh" ]
