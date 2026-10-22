FROM ubuntu:20.04

WORKDIR /opt/ds4
COPY ds4-server ds4 /opt/ds4/
COPY lib/ /opt/ds4/lib/
COPY entrypoint.sh /opt/ds4/entrypoint.sh
RUN chmod +x /opt/ds4/ds4 /opt/ds4/ds4-server /opt/ds4/entrypoint.sh

ENV LD_LIBRARY_PATH=/opt/ds4/lib
ENTRYPOINT ["/opt/ds4/entrypoint.sh"]