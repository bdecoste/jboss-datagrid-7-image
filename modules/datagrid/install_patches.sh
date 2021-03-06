#!/bin/sh

set -e

SOURCES_DIR=/tmp/artifacts
LUCENE_CVE_PATCH="jboss-datagrid-7.1.0-CVE-2017-12629-server-patch.zip"

$JBOSS_HOME/bin/cli.sh -Dorg.wildfly.patching.jar.invalidation=true --command="patch apply $SOURCES_DIR/$LUCENE_CVE_PATCH"

function remove_scrapped_jars {
  find $JBOSS_HOME -name \*.jar.patched -printf "%h\n" | sort | uniq | xargs rm -rv
}

function update_permissions {
  chown -R jboss:root $JBOSS_HOME
  chmod 0755 $JBOSS_HOME
  chmod -R g+rwX $JBOSS_HOME
}

function aggregate_patched_modules {
  export JBOSS_PIDFILE=/tmp/jboss.pid
  cp -r $JBOSS_HOME/standalone /tmp/

  $JBOSS_HOME/bin/standalone.sh --admin-only -Djboss.server.base.dir=/tmp/standalone &

  start=$(date +%s)
  end=$((start + 120))
  until $JBOSS_HOME/bin/cli.sh --command="connect" || [ $(date +%s) -ge "$end" ]; do
    sleep 5
  done

  timeout 30 $JBOSS_HOME/bin/cli.sh --connect --command="/core-service=patching:ageout-history"
  timeout 30 $JBOSS_HOME/bin/cli.sh --connect --command="shutdown"

  # give it a moment to settle
  for i in $(seq 1 10); do
      test -e "$JBOSS_PIDFILE" || break
      sleep 1
  done

  # EAP still running? something is not right
  if test -e "$JBOSS_PIDFILE"; then
      echo "JDG instance still running; aborting" >&2
      exit 1
  fi

  rm -rf /tmp/standalone
}

aggregate_patched_modules
remove_scrapped_jars
update_permissions
