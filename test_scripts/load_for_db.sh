#!/bin/bash

db_ip="db_ip"
db_user="db_user"
db_password="db_password"
db_port="db_port"
db_name="db_name"


psql postgresql://$db_user:$db_password@$db_ip:$db_port/$db_name -c "
    CREATE TABLE IF NOT EXISTS article (
        article_id bigserial primary key,
        article_name varchar(20) NOT NULL,
        article_desc text NOT NULL,
        date_added timestamp default NULL
    );
"
for ((i = 0; i < 5000; i++)) do
    psql postgresql://$db_user:$db_password@$db_ip:$db_port/$db_name -c "
        INSERT INTO article
        (article_name, article_desc)
        VALUES ('123', '123')
    "
done
