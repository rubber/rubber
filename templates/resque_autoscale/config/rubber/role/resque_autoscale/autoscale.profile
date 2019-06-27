<%
  @path = "/etc/profile.d/autoscale.sh"
%>

SSH_AGENT_PIDS=`pgrep -U $USER ssh-agent`
for PID in $SSH_AGENT_PIDS; do
    let "FPID = $PID - 1"
    FILE=`find /tmp -path "*ssh*" -type s -iname "agent.$FPID"`
    export SSH_AGENT_PID="$PID"
    export SSH_AUTH_SOCK="$FILE"
done

# start agent and set environment variables, if needed
if ! env | grep -q SSH_AGENT_PID >/dev/null; then
  echo "Starting ssh agent"
  eval $(ssh-agent -s)
  <% rubber_env.autoscale_authorization_keys.each do |key| %>
     ssh-add -t 0 <%= key %> &> /dev/null
  <% end %>
fi