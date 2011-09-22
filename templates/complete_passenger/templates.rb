database_engines = ['mysql', 'postgresql']
if ! database_engines.any? {|d| @template_dependencies.include?(d)}
  db = Rubber::Util::prompt("DATABASE",
                            "The database engine to use (#{database_engines.join(', ')})",
                            true,
                            'mysql')
  template_dependencies << db
end

