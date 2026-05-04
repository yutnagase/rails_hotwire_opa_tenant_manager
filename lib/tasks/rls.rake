namespace :rls do
  desc "Grant table/sequence privileges to the RLS role (rails_user)"
  task grant: :environment do
    role = ENV.fetch("RLS_ROLE", "rails_user")
    conn = ActiveRecord::Base.connection

    conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{conn.quote_column_name(role)};")
    conn.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{conn.quote_column_name(role)};")
    conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{conn.quote_column_name(role)};")
    conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO #{conn.quote_column_name(role)};")

    puts "RLS privileges granted to #{role}."
  end
end

# Automatically run after db:migrate and db:schema:load (used by db:setup/db:reset)
%w[db:migrate db:schema:load].each do |task_name|
  Rake::Task[task_name].enhance do
    Rake::Task["rls:grant"].invoke
  end
end
