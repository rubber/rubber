<%
  is_old_ubuntu = %w[10.04 12.04].include?(rubber_instance.os_version)

  @path = "#{rubber_env.graphite_dir}/conf/graphite.wsgi"
  @skip = ! is_old_ubuntu
%>
import os, sys
sys.path.append('/opt/graphite/webapp')
os.environ['DJANGO_SETTINGS_MODULE'] = 'graphite.settings'

import django.core.handlers.wsgi

application = django.core.handlers.wsgi.WSGIHandler()
