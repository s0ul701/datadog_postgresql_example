FROM postgres:12.4-alpine

RUN mkdir ./pg_logs
RUN chmod -R 777 /pg_logs
RUN chown -R postgres /pg_logs

COPY ./init.sh /docker-entrypoint-initdb.d
COPY ./postgresql.conf /etc/postgresql/postgresql.conf
