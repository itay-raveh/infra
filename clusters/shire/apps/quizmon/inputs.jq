def required_string($label):
  if type != "string" or length == 0 then error("missing " + $label) else . end;
def secret($name; $data):
  {apiVersion: "v1", kind: "Secret", metadata: {namespace: "quizmon", name: $name}, stringData: $data};
def password($name):
  .database_passwords[$name] | required_string("database password: " + $name);
.database_host |= required_string("database host") |
if (.database_host | test("^[a-z0-9-]+([.][a-z0-9-]+)+$")) | not then error("invalid database host") else . end |
if $mode == "database" then
  . as $inputs |
  [
    (["quizmon", "app"]) as $role |
    secret("quizmon-db-" + $role[1]; {username: $role[0], password: ($inputs | password($role[0]))}) |
    .type = "kubernetes.io/basic-auth"
  ] + [
    secret("quizmon-dns"; {token: (.dns_token | required_string("DNS token"))})
  ]
elif $mode == "release" then
  if (.hyperdrive_id | type) != "string" or
     ((.hyperdrive_id | test("^[a-fA-F0-9]{32}$")) | not) or
     .hyperdrive_id == "00000000000000000000000000000000" then
    error("Hyperdrive must be provisioned before generating release inputs")
  else . end |
  [
    secret("quizmon-migration"; {"migration-connection.json": {
      host: .database_host, port: 5432, database: "quizmon",
      user: "quizmon", password: password("quizmon")
    } | tojson})
  ]
else error("mode must be database or release") end
