# --- setup ---
# Give each workspace its own database by prefixing with the workspace name
export DATABASE_PREFIX="${CONDUCTOR_WORKSPACE_NAME}-"

bundle install
bin/rails db:prepare
RAILS_ENV=test bin/rails db:prepare

# --- run ---
export DATABASE_PREFIX="${CONDUCTOR_WORKSPACE_NAME}-"
PORT=$CONDUCTOR_PORT bin/dev

# --- archive ---
export DATABASE_PREFIX="${CONDUCTOR_WORKSPACE_NAME}-"

bin/rails db:drop
RAILS_ENV=test bin/rails db:drop

bin/rails log:clear tmp:clear
