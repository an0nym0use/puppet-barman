# == Class: postgres
#
# This class export resources to the Barman server (Barman configurations,
# cron, SSH key) and import resources from it (configure 'archive_mode',
# define user used by Barman to connect into PostgreSQL database(s)).
#
# === Parameters
#
# [*host_group*] - Tag the different host groups for the backup
#                  (default value is set from the 'settings' class).
# [*wal_level*] - Configuration of the 'wal_level' parameter in the postgresql.conf
#                 file. The default value is 'archive'.
# [*barman_user*] - Definition of the 'barman' user used in Barman 'conninfo'. The
#                   default value is set from the 'settings' class.
# [*barman_dbuser*] - Definition of the user used by Barman to connect to the
#                     PostgreSQL database(s) in the 'conninfo'. The default value is
#                     set from the 'settings' class.
# [*barman_home*] - Definition of the barman home directory. The default value
#                   is set from the 'settings' class.
# [*backup_mday*] - Day of the month set in the cron for the backup schedule.
#                   The default value (undef) ensure daily backups.
# [*backup_wday*] - Day of the week set in the cron for the backup schedule.
#                   The default value (undef) ensure daily backups.
# [*backup_hour*] - Hour set in the cron for the backup schedule. The default
#                   value is 04:XXam.
# [*backup_minute*] - Minute set in the cron for the backup schedule. The default
#                     value is for XX:00am
# [*password*] - Password used by Barman to connect to PosgreSQL. The default
#                value (empty string) allows the generation of a random password.
# [*server_address*] - The whole fqdn of the PostgreSQL server used in Barman
#                      'ssh_command' (automatically configured by Puppet).
# [*postgres_server_id*] - Id of the PostgreSQL server, given by its host name
#                          (automatically configured by Puppet).
# [*postgres_user*] - The PostgreSQL user used in Barman 'ssh_command'.
#
# === Examples
#
# The class can be used right away with defaults:
# ---
#  include postgres
# ---
#
# All parameters that are supported by barman can be changed:
# ---
#  class { postgres :
#    backup_hour   => 4,
#    backup_minute => 0,
#    password      => 'not_needed',
#    postgres_user => 'postgres',
#  }
# ---
#
# === Authors
#
# * Giuseppe Broccolo <giuseppe.broccolo@2ndQuadrant.it>
# * Giulio Calacoci <giulio.calacoci@2ndQuadrant.it>
# * Francesco Canovai <francesco.canovai@2ndQuadrant.it>
# * Marco Nenciarini <marco.nenciarini@2ndQuadrant.it>
# * Gabriele Bartolini <gabriele.bartolini@2ndQuadrant.it>
#
# Many thanks to Alessandro Franceschi <al@lab42.it>
#
# === Past authors
#
# Alessandro Grassi <alessandro.grassi@devise.it>
#
# === Copyright
#
# Copyright 2012-2014 2ndQuadrant Italia (Devise.IT SRL)
#
class barman::postgres (
  $host_group     = $::barman::settings::host_group,
  $wal_level      = 'archive',
  $barman_user    = $::barman::settings::user,
  $barman_dbuser  = $::barman::settings::dbuser,
  $barman_dbname  = $::barman::settings::dbname,
  $barman_home    = $::barman::settings::home,
  $backup_mday    = undef,
  $backup_wday    = undef,
  $backup_hour    = 4,
  $backup_minute  = 0,
  $password       = '',
  $server_address = $::fqdn,
  $postgres_server_id = $::hostname,
  $postgres_user      = 'postgres',
) inherits ::barman::settings {

  unless defined(Class['postgresql::server']) {
    fail('barman::server requires the postgresql::server module installed and configured')
  }

  # Generate a new password if not defined
  $real_password = $password ? {
    ''      => fqdn_rand('30','fwsfbsfw'),
    default => $password,
  }

  # Configure PostgreSQL server for archive mode
  postgresql::server::config_entry {
    'archive_mode': value => 'on';
    'wal_level': value => "${wal_level}";
  }

  # define user used by Barman to connect into PostgreSQL database(s)
  postgresql::server::role { $barman_dbuser:
    login         => true,
    password_hash => postgresql_password($barman_dbuser, $real_password),
    superuser     => true,
  }

  # Collect resources exported by Barman server
  Barman::Archive_command <<| tag == "barman-${host_group}" |>> {
    postgres_server_id => $postgres_server_id,
  }

  Postgresql::Server::Pg_hba_rule <<| tag == "barman-${host_group}" |>>

  Ssh_authorized_key <<| tag == "barman-${host_group}" |>> {
    require => Class['postgresql::server'],
  }

  # Export resources to Barman server
  @@barman::server { $::hostname:
    conninfo    => "user=${barman_dbuser} dbname=${barman_dbname} host=${server_address}",
    ssh_command => "ssh ${postgres_user}@${server_address}",
    tag         => "barman-${host_group}",
  }

  @@cron { "barman_backup_${::hostname}":
    command    => "[ -x /usr/bin/barman ] && /usr/bin/barman -q backup ${::hostname}",
    user       => 'root',
    monthday   => $backup_mday,
    weekday    => $backup_wday,
    hour       => $backup_hour,
    minute     => $backup_minute,
    tag        => "barman-${host_group}",
  }

  # Fill the .pgpass file
  @@file_line { "barman_pgpass_content-${::hostname}":
    path   => "${barman_home}/.pgpass",
    line   => "${server_address}:*:${barman_dbname}:${barman_dbuser}:${real_password}",
    tag    => "barman-${host_group}",
  }

  # Ssh key of 'postgres' user in PostgreSQL server
  if ($::postgres_key != undef and $::postgres_key != '') {
    $postgres_key_splitted = split($::postgres_key, ' ')
    @@ssh_authorized_key { "postgres-${::hostname}":
      ensure  => present,
      user    => $barman_user,
      type    => $postgres_key_splitted[0],
      key     => $postgres_key_splitted[1],
      tag     => "barman-${host_group}-postgresql",
    }
  }
}
