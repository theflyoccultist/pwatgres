# frozen_string_literal: true

require 'colorize'
require 'dotenv/load'
require 'pg'
require 'readline'
require 'securerandom'

puts("


#  ██▓███   █     █░ ▄▄▄     ▄▄▄█████▓  ▄████  ██▀███  ▓█████   ██████
# ▓██░  ██▒▓█░ █ ░█░▒████▄   ▓  ██▒ ▓▒ ██▒ ▀█▒▓██ ▒ ██▒▓█   ▀ ▒██    ▒
# ▓██░ ██▓▒▒█░ █ ░█ ▒██  ▀█▄ ▒ ▓██░ ▒░▒██░▄▄▄░▓██ ░▄█ ▒▒███   ░ ▓██▄
# ▒██▄█▓▒ ▒░█░ █ ░█ ░██▄▄▄▄██░ ▓██▓ ░ ░▓█  ██▓▒██▀▀█▄  ▒▓█  ▄   ▒   ██▒
# ▒██▒ ░  ░░░██▒██▓  ▓█   ▓██▒ ▒██▒ ░ ░▒▓███▀▒░██▓ ▒██▒░▒████▒▒██████▒▒
# ▒▓▒░ ░  ░░ ▓░▒ ▒   ▒▒   ▓▒█░ ▒ ░░    ░▒   ▒ ░ ▒▓ ░▒▓░░░ ▒░ ░▒ ▒▓▒ ▒ ░
# ░▒ ░       ▒ ░ ░    ▒   ▒▒ ░   ░      ░   ░   ░▒ ░ ▒░ ░ ░  ░░ ░▒  ░ ░
# ░░         ░   ░    ░   ▒    ░      ░ ░   ░   ░░   ░    ░   ░  ░  ░
#              ░          ░  ░              ░    ░        ░  ░      ░


  ")

# Prompt user for input
def prompt(message)
  Readline.readline(message, true).strip
end

# Runs queries and handles errors
def run_query(conn, sql, context = 'Unnamed Query')
  puts "Executing: #{context}".colorize(:light_black)
  conn.exec(sql)
rescue PG::Error => e
  puts "💀 Failed at: #{context}".colorize(:red)
  puts "💀 PostgreSQL says: #{e.message}".colorize(:red)
  exit 1
end

puts('PostgreSQL CLI tool to automate setup for your project'.colorize(:cyan))

USER = prompt('> New User: ')
PASSWORD = SecureRandom.alphanumeric(26)
PROJECT_DB = prompt('> New Database name: ')
SCHEMA = prompt('> Schema name: ')

begin
  # Establish PostgreSQL connection as admin
  conn = PG.connect(
    dbname: 'postgres',
    user: ENV['PG_CLI_USER'],
    password: ENV['PG_CLI_PASS'],
    host: '/var/run/postgresql'
  )

  puts "Setting up PostgreSQL database for #{USER}...".colorize(:light_blue)

  run_query(conn, "CREATE USER #{PG::Connection.quote_ident(USER)} WITH PASSWORD '#{PASSWORD}';", 'Create User')

  run_query(conn, "GRANT #{PG::Connection.quote_ident(USER)} TO #{PG::Connection.quote_ident(ENV['PG_CLI_USER'])};",
            'Grant User Role to the Admin user')

  run_query(conn, "CREATE DATABASE #{PG::Connection.quote_ident(PROJECT_DB)}
            OWNER #{PG::Connection.quote_ident(USER)};", 'Create the database and assign ownership to the user')

  # Reconnect to the new database for schema operations
  conn.close
  conn = PG.connect(
    dbname: PROJECT_DB,
    user: ENV['PG_CLI_USER'],
    password: ENV['PG_CLI_PASS'],
    host: '/var/run/postgresql'
  )

  run_query(conn, "CREATE SCHEMA #{PG::Connection.quote_ident(SCHEMA)}
            AUTHORIZATION #{PG::Connection.quote_ident(USER)};", 'Create Custom Schema')
  run_query(conn, "ALTER DATABASE #{PG::Connection.quote_ident(PROJECT_DB)} SET search_path TO
            #{PG::Connection.quote_ident(SCHEMA)};", 'Grant privileges')

  run_query(conn, "GRANT USAGE ON SCHEMA #{PG::Connection.quote_ident(SCHEMA)}
            TO #{PG::Connection.quote_ident(USER)};", 'Grant usage on schema')
  run_query(conn, "GRANT CREATE ON SCHEMA #{PG::Connection.quote_ident(SCHEMA)}
            TO #{PG::Connection.quote_ident(USER)};", 'Granting Create on Schema')

  run_query(conn, "ALTER DEFAULT PRIVILEGES FOR ROLE #{PG::Connection.quote_ident(USER)} IN SCHEMA
            #{PG::Connection.quote_ident(SCHEMA)} GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
            TO #{PG::Connection.quote_ident(USER)};", 'Set default privileges for future tables')
  run_query(conn, "ALTER DEFAULT PRIVILEGES FOR ROLE #{PG::Connection.quote_ident(USER)} IN SCHEMA
            #{PG::Connection.quote_ident(SCHEMA)} GRANT USAGE, SELECT, UPDATE ON SEQUENCES
            TO #{PG::Connection.quote_ident(USER)};", 'Set default privileges for future sequences')

  run_query(conn, "ALTER USER #{PG::Connection.quote_ident(USER)} WITH NOCREATEDB NOCREATEROLE;",
            'Locking down user abilities')

  puts "\n😻 Database setup complete for '#{PROJECT_DB}' with user '#{USER}'!".colorize(:green)

  puts 'important informations below!'.colorize(:green)
  puts "\nSchema Name: #{SCHEMA}".colorize(:light_blue)
  puts "DB Name: #{PROJECT_DB}".colorize(:light_blue)
  puts "User Name: #{USER}".colorize(:yellow)
  puts "Generated password: #{PASSWORD}".colorize(:yellow)

  puts "\n🔮 DATABASE_URL=".colorize(:magenta) +
       "postgres://#{USER}:#{PASSWORD}@localhost/#{PROJECT_DB}".colorize(:light_white)
ensure
  conn&.close
end
