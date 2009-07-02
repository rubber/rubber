<%
  @path = "#{RUBBER_ROOT}/config/initializers/mysql_cluster_migrations.rb"
%>

# mysql adapter in rails hardcodes engine to be innodb, so if we want all
# rails tables to be clustered, we need to override this behavior
#
class ActiveRecord::ConnectionAdapters::MysqlAdapter
  def create_table(table_name, options = {}) #:nodoc:
    super(table_name, options.reverse_merge(:options => "ENGINE=ndbcluster"))
  end
end

