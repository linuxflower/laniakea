FROM debian:testing

# prepare
ENV LANG C.UTF-8
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update -qq

# set up Postgres with debversion extension for use in Laniakea testssuite
RUN apt-get install -yq \
    postgresql-10 \
    postgresql-10-debversion

RUN echo "/etc/init.d/postgresql start && exit 0" > /etc/rc.local
RUN /etc/init.d/postgresql start && \
    su postgres -c "psql -c \"CREATE DATABASE laniakea_test;\" " && \
    su postgres -c "psql -c \"CREATE USER lkdbuser_test WITH PASSWORD 'notReallySecret';\" " && \
    su postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE laniakea_test to lkdbuser_test;\" " && \
    su postgres -c "psql -c \"CREATE EXTENSION IF NOT EXISTS debversion;\" laniakea_test"

USER postgres
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/10/main/pg_hba.conf

RUN echo "listen_addresses='*'" >> /etc/postgresql/10/main/postgresql.conf
EXPOSE 5432

CMD ["/usr/lib/postgresql/10/bin/postgres", "-D", "/var/lib/postgresql/10/main", "-c", "config_file=/etc/postgresql/10/main/postgresql.conf"]
