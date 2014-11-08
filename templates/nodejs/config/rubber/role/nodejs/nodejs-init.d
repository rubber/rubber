<%
  @path = "/etc/init.d/nodejs"
  @perms = 0755
  current_path = "/mnt/#{rubber_env.app_name}-#{Rubber.env}/current"
  log_dir = "/mnt/#{rubber_env.app_name}-#{Rubber.env}/shared/log"
  app_dir = "#{current_path}/#{rubber_env.nodejs.app_dir}"
%>

#!/bin/sh

# Adapted from https://github.com/chovy/node-startup

NODE_ENV="production"
PORT="<%= rubber_env.nodejs.port %>"
APP_DIR="<%= app_dir %>"
NODE_APP="<%= rubber_env.nodejs.app_file %>"
CONFIG_DIR="$APP_DIR"
PID_DIR="<%= rubber_env.nodejs.pid_dir %>"
PID_FILE="$PID_DIR/<%= rubber_env.nodejs.pid_file %>"
LOG_DIR="<%= log_dir %>"
LOG_FILE="$LOG_DIR/nodejs.log"
NODE_EXEC=$(which node)

USAGE="Usage: $0 {start|stop|restart|status} [--force]"
FORCE_OP=false

pid_file_exists() {
  [ -f "$PID_FILE" ]
}

get_pid() {
  echo "$(cat "$PID_FILE")"
}

is_running() {
  PID=$(get_pid)
  ! [ -z "$(ps ef | awk '{print $1}' | grep "^$PID$")" ]
}

start_it() {
  mkdir -p "$PID_DIR"
  mkdir -p "$LOG_DIR"

  echo "Starting node app ..."

  PORT="$PORT" NODE_ENV="$NODE_ENV" NODE_CONFIG_DIR="$CONFIG_DIR" $NODE_EXEC "$APP_DIR/$NODE_APP"  1>"$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "Node app started with pid $!"
}

stop_process() {
  PID=$(get_pid)
  echo "Killing process $PID"
  kill $PID
}

remove_pid_file() {
  echo "Removing pid file"
  rm -f "$PID_FILE"
}

start_app() {
  if pid_file_exists
  then
    if is_running
    then
      PID=$(get_pid)
      echo "Node app already running with pid $PID"
      exit 1
    else
      echo "Node app stopped, but pid file exists"
      if [ $FORCE_OP = true ]
      then
        echo "Forcing start anyways ..."
        remove_pid_file
        start_it
      fi
    fi
  else
    start_it
  fi
}

stop_app() {
  if pid_file_exists
  then
    if is_running
    then
      echo "Stopping node app ..."
      stop_process
      remove_pid_file
      echo "Node app stopped"
    else
      echo "Node app already stopped, but pid file exists"
      if [ $FORCE_OP = true ]
      then
        echo "Forcing stop anyways ..."
        remove_pid_file
        echo "Node app stopped"
      fi
    fi
  else
    echo "Node app already stopped, pid file does not exist"
  fi
}

status_app() {
  if pid_file_exists
  then
    if is_running
    then
      PID=$(get_pid)
      echo "Node app running with pid $PID"
    else
      echo "Node app stopped, but pid file exists"
    fi
  else
    echo "Node app stopped"
  fi
}

case "$2" in
  --force)
    FORCE_OP=true
  ;;

  "")
  ;;

  *)
    echo $USAGE
    exit 1
  ;;
esac

case "$1" in
  start)
    start_app
  ;;

  stop)
    stop_app
  ;;

  restart)
    stop_app
    start_app
  ;;

  status)
    status_app
  ;;

  *)
    echo $USAGE
    exit 1
  ;;
esac
