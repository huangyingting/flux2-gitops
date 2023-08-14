# PostgREST

## Tutorial

Run `psql -U postgres` to login to postgres

```sql
create database postgrest;
```

Connect to postgrest database
`\c postgrest`

Run
```sql
create schema api;
create table api.todos (
  id serial primary key,
  done boolean not null default false,
  task text not null,
  due timestamptz
);

insert into api.todos (task) values
  ('learn azure'), ('learn aws');

create role web_anon nologin;

grant usage on schema api to web_anon;
grant select,insert,update,delete on api.todos to web_anon;
grant usage, select on sequence api.todos_id_seq to web_anon;

create role authenticator noinherit login password 'password';
grant web_anon to authenticator;
```

Send cURL commands

GET
```bash
curl http://localhost:3000/todos
```

POST
```bash
curl http://localhost:3000/todos -X POST \
     -H "Content-Type: application/json" \
     -d '{"task": "learn gcp"}'
```
