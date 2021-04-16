# Настройка связки DataDog + PostgreSQL

[DataDog](https://www.datadoghq.com/) - система мониторинга состояния сервера, обладающая широким спектром возможностей.
Данная система является клиент-серверной, т.е. на контролируемом сервере устанавливается ТОЛЬКО агент, который отсылает метрики на сервера DataDog.

---

## Подготовка

1. [Регистрация](https://app.datadoghq.com/signup) (создание личного кабинета на стороне DataDog, откуда и осуществляется мониторинг)
2. [Получение API-ключа](https://app.datadoghq.eu/account/settings#api)

---

## 1. Подключение Docker-интеграции

Данная интеграция позволяет мониторить состояние запущенных на сервере контейнеров (на достаточно высоком уровне абстракции: CPU, RAM, I/O и т.д.), не анализируя специфичные для запущенных в контейнерах приложений метрики.

***./docker-compose.yml:***

```yaml
version: '3.3'
services:
    ...other services...

    datadog-agent:
        image: datadog/agent:7.26.0-jmx
        env_file:
            - ./datadog/.env
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro  # с помощью вольюмов осуществляется
            - /proc/:/host/proc/:ro                         # сбор метрик с контейнеров/сервера
            - /sys/fs/cgroup/:/host/sys/fs/cgroup:ro

    ...more other services...
```

***./datadog.env:***

```yaml
DD_API_KEY=<YOUR_DATADOG_API_KEY>
DD_SITE=<YOUR_DATADOG_DOMEN>

DD_PROCESS_AGENT_ENABLED=true   # позволяет просматривать процессы сервера/контейнеров в DataDog
```

Результаты настроек доступны по [ссылке](https://app.datadoghq.eu/containers):

*Ссылки*:

1. [Документация](https://docs.datadoghq.com/integrations/faq/compose-and-the-datadog-agent/) по базовой настройке связки DataDog/Docker/Docker Compose;
2. Базовая [документация](https://docs.datadoghq.com/agent/docker/?tab=standard) по Datadog Agent.

<br>

## 2. Подключение PostgreSQL-интеграции

Данная интеграция позволяет отслеживать специфичные для PostgreSQL метрики (занимаемое на диске место, количество таблиц, количество созданных/удаленных/измененных строк и т.д.) и его логи.

***./docker-compose.yml:***

```yaml
version: '3.3'
services:
    ...other services...

    db:
        build:                          # кастомный образ необходим для задания
            context: ./db               # PostgreSQL`у кастомного файла настроек
            dockerfile: ./Dockerfile    # и начальной инициализации для DataDog
        command: ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]  # задание PostgreSQL`у кастомного файла настроек
        env_file:
            - ./db/.env
            - ./datadog.env
        ports:
            - 5432:5432
        volumes:
            - ./pg_logs:/pg_logs    # вольюм для хранения папки (файла) с логами
        labels:
            com.datadoghq.ad.check_names: '["postgres"]'    # на основе этого лейбла DataDog определяет, какое приложение работает в контейнере (не менять!)
            com.datadoghq.ad.init_configs: '[{}]'   # инициализирующие настройки для взаимодействия DataDog и PostgreSQL (не менять!)
            com.datadoghq.ad.instances: >-  # основной блок настройки соединения DataDog и PostgreSQL
                [{
                    "host": "%%host%%", # вместо этой шаблонной переменной DataDog подставляет IP-адрес контейнера с PostgreSQL
                    "port": "%%port%%",   # порт PostgreSQL
                    "username": "%%env_DATADOG_DB_USER%%",  # вместо этой шаблонной переменной DataDog подставляет значение переменной окружения DATADOG_DB_USER
                    "password": "%%env_DATADOG_DB_PASSWORD%%",   # вместо этой шаблонной переменной DataDog подставляет значение переменной окружения DATADOG_DB_PASSWORD
                    "collect_activity_metrics": "true", # разрешение сбора метрик транзакций
                    "relations": [{             # задание имен таблиц, 
                        "relation_regex": ".*"  # статистику которых 
                    }]                          # нужно мониторить
                }]
            com.datadoghq.ad.logs: >-
                [{
                    "type": "file", # тип источника логов
                    "source": "postgresql", # название интеграции (не менять!)
                    "service": "postgresql",  # имя сервиса для отображение в UI DataDog
                    "path": "/pg_logs/pg.log",  # путь до файла с логами (внутри контейнера DataDog-агента!)
                    "log_processing_rules": [{  # блок правил обработки логов
                        "type": "multi_line",   # сообщение DataDog`у о том, что логи могут быть многострочными
                        "name": "logs",
                        "pattern" : "\\d{4}-(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01])" # паттерн начала унарного лог-сообщения
                    }]
                }]

    datadog-agent:
        image: datadog/agent:7.26.0-jmx
        env_file:
            - ./datadog.env
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - /proc/:/host/proc/:ro
            - /sys/fs/cgroup/:/host/sys/fs/cgroup:ro
            - /opt/datadog-agent/run:/opt/datadog-agent/run:rw  # вольюм позволяет сохранять логи локально на случай непредвиденных ситуаций
            - ./pg_logs:/pg_logs    # вольюм прокидывает логи PostgreSQL-контейнера в DataDog-контейнер

    ...more other services...
```

***./db/Dockerfile:***

```Dockerfile
FROM postgres:12.4-alpine

RUN mkdir ./pg_logs             # создание директории
RUN chmod -R 777 /pg_logs       # для лог-файла
RUN chown -R postgres /pg_logs  # с необходимыми правами

COPY ./init.sh /docker-entrypoint-initdb.d  # копирование инициализационного для DataDog`а скрипта
COPY ./postgresql.conf /etc/postgresql/postgresql.conf  # копирование кастомного конфиг-файла для PostgreSQL
```

***./db/.env:***

```configuration
POSTGRES_DB=<DB_NAME>
POSTGRES_USER=<DB_USER>
POSTGRES_PASSWORD=<USER_PASSWORD>
```

***./db/init.sh:***

```bash
#!/bin/bash

psql -c "
    CREATE USER $DATADOG_DB_USER WITH PASSWORD '$DATADOG_DB_PASSWORD';
    GRANT pg_monitor TO $DATADOG_DB_USER;                   # выдача необходимых
    GRANT SELECT ON pg_stat_database TO $DATADOG_DB_USER;   # для мониторинга
    GRANT SELECT ON pg_stat_activity TO $DATADOG_DB_USER;   # прав
"
```

***./db/postgresql.conf:***

```configuration
...other configs...

logging_collector = on  # перенаправление логов в файл
log_directory = '/pg_logs'  # директория с логами
log_filename = 'pg.log' # название файла с логами
log_file_mode = 0644    # права лог-файла
log_min_messages = info         # задание минимального
log_min_error_statement = info  # записываемых лог-сообщений
log_min_duration_statement = 0  # минимальное необходимое время выполнения запроса для попадания его в лог-файл (в миллисекундах)
log_line_prefix = '%m [%p] %d %a %u %h %c ' # формат префикса лог-сообщений

...more other configs...
```

***./datadog.env:***

```yaml
DD_API_KEY=<DATADOG_API_KEY>
DD_SITE=<DATADOG_DOMEN>

DATADOG_DB_USER=<DATADOG_DB_USER>   # имя пользоваеля и его пароль,
DATADOG_DB_PASSWORD=<DATADOG_DB_PASSWORD>   # под которым DataDog просматривает PostgreSQL

DD_PROCESS_AGENT_ENABLED=true   # позволяет DataDog-агенту просматривать процессы сервера/контейнеров в DataDog
DD_LOGS_ENABLED=true    # позволяет DataDog-агенту собирать логи с сервера/контейнеров
DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true   # включает у DataDog-агента сбор логов со всех контейнеров
```

./test_scripts/load_for_db.sh -- скрипт для создания тестовой нагрузки на БД для проверки корректности произведенных настроек.

Ссылки:

1. Базовая [документация](https://docs.datadoghq.com/integrations/postgres/?tab=containerized) по настройке PostgreSQL-интеграции в Docker;
2. Серия [статей](https://www.datadoghq.com/blog/collect-postgresql-data-with-datadog/) по advanced-настройке PostgreSQL-интеграции;
3. Описание таблиц [pg_stat_database/pg_stat_activity](https://postgrespro.ru/docs/postgresql/12/monitoring-stats);
4. Пример [postgresql.conf](https://github.com/postgres/postgres/blob/master/src/backend/utils/misc/postgresql.conf.sample) с подробным описанием настроек;
5. [Статья](https://docs.datadoghq.com/agent/docker/log/?tab=dockercompose) по настройке логирования DataDog-агентом;
6. [Статья](https://docs.datadoghq.com/agent/docker/integrations/?tab=docker) по настройке автообнаружения интеграций DataDog-агентом;
7. [Документация](https://docs.datadoghq.com/agent/faq/template_variables/) по шаблонным переменным.
