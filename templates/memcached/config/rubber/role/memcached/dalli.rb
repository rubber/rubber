<%
  @path = "#{Rubber.root}/config/dalli.rb"
%>

module Rubber
  module Dalli
    module Config
      include ::Rails::Initializable

      initializer :set_dalli_cache, :before => :initialize_cache do |app|
        config.action_controller.perform_caching = true
        config.cache_store = :dalli_store,
<%- rubber_instances.for_role('memcached').each do |ic| %>
            '<%= ic.full_name %>:<%= rubber_env.memcached_port %>',
<%- end %>
            { :value_max_bytes => <%= rubber_env.memcached_max_slab_bytes %> }
      end
    end
  end
end
