def required_string($label):
  if type != "string" or length == 0 then error("missing " + $label) else . end;
def secret($name; $data):
  {apiVersion: "v1", kind: "Secret", metadata: {namespace: "quizmon", name: $name}, stringData: $data};
def password($name):
  .database_passwords[$name] | required_string("database password: " + $name);
def uri($role; $database):
  "postgresql://\($role):\(password($role) | @uri)@\(.database_host):5432/\($database)?sslmode=verify-full";

.database_host |= required_string("database host") |
if (.database_host | test("^[a-z0-9-]+([.][a-z0-9-]+)+$")) | not then error("invalid database host") else . end |
if $mode == "database" then
  . as $inputs |
  [
    (["quizmon", "app"], ["powersync_source", "source"], ["powersync_storage", "storage"]) as $role |
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
  if (.auth_secret | type) != "string" or (.auth_secret | length) < 32 then
    error("missing authentication secret")
  else . end |
  if ($worker[0].VAPID_PRIVATE_KEY | type) != "string" or
     (($worker[0].VAPID_PRIVATE_KEY | test("^[A-Za-z0-9_-]{43}$")) | not) then
    error("provide the existing VAPID_PRIVATE_KEY in a JSON file")
  else . end |
  if (.cloudflare.accountId | type) != "string" or
     ((.cloudflare.accountId | test("^[a-f0-9]{32}$")) | not) then
    error("invalid Cloudflare account ID")
  else . end |
  .cloudflare.token |= required_string("Cloudflare deployment token") |
  [
    secret("quizmon-worker"; {"worker-secrets.json": {
      BETTER_AUTH_SECRET: .auth_secret,
      VAPID_PRIVATE_KEY: $worker[0].VAPID_PRIVATE_KEY
    } | tojson}),
    secret("quizmon-cloudflare"; {"cloudflare.json": (.cloudflare | tojson)}),
    secret("quizmon-migration"; {"migration-connection.json": {
      version: 1, host: .database_host, port: 5432, database: "quizmon",
      user: "quizmon", password: password("quizmon")
    } | tojson}),
    secret("quizmon-sync-source"; {uri: uri("powersync_source"; "quizmon")}),
    secret("quizmon-sync-storage"; {uri: uri("powersync_storage"; "powersync")})
  ]
else error("mode must be database or release") end
