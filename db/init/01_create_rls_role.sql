DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rails_user') THEN
    CREATE ROLE rails_user WITH LOGIN PASSWORD 'rails_password' NOSUPERUSER NOBYPASSRLS;
  END IF;
END $$;
