#!/bin/bash
### BEGIN INIT INFO
# Provides:          clickhouse-server
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Required-Start:
# Required-Stop:
# Short-Description: Yandex clickhouse-server daemon
### END INIT INFO

source conf/env.ini
BASE_DIR=${install_dir}
CH_ID=${ch_id}
CLICKHOUSE_LOGDIR=${BASE_DIR}/log
CLICKHOUSE_LOGDIR_USER=root
LOCALSTATEDIR=/var/lock

CLICKHOUSE_CRONFILE=""
CLICKHOUSE_CONFIG=${BASE_DIR}/conf/config.xml
LOCKFILE=${LOCALSTATEDIR}/${PROGRAM}_${CH_ID}
RETVAL=0

CLICKHOUSE_PIDDIR=/var/run/$PROGRAM
CLICKHOUSE_PIDFILE="${CLICKHOUSE_PIDDIR}/${PROGRAM}_${CH_ID}.pid"

echo "BASE_DIR=${BASE_DIR}"
echo "CH_ID=${CH_ID}"
echo "clickhouse_logdir=${CLICKHOUSE_LOGDIR}"
echo "clickhouse_logdir_user=${CLICKHOUSE_LOGDIR_USER}"
echo "clickhouse_conf=${CLICKHOUSE_CONFIG}"
echo "clickhouse_pidfile=${CLICKHOUSE_PIDFILE}"

# On x86_64, check for required instruction set.
if uname -mpi | grep -q 'x86_64'; then
    if ! grep -q 'sse4_2' /proc/cpuinfo; then
        # On KVM, cpuinfo could falsely not report SSE 4.2 support, so skip the check.
        if ! grep -q 'Common KVM processor' /proc/cpuinfo; then

            # Some other VMs also report wrong flags in cpuinfo.
            # Tricky way to test for instruction set:
            #  create temporary binary and run it;
            #  if it get caught illegal instruction signal,
            #  then required instruction set is not supported really.
            #
            # Generated this way:
            # gcc -xc -Os -static -nostdlib - <<< 'void _start() { __asm__("pcmpgtq %%xmm0, %%xmm1; mov $0x3c, %%rax; xor %%rdi, %%rdi; syscall":::"memory"); }' && strip -R .note.gnu.build-id -R .comment -R .eh_frame -s ./a.out && gzip -c -9 ./a.out | base64 -w0; echo

            if ! (echo -n 'H4sICAwAW1cCA2Eub3V0AKt39XFjYmRkgAEmBjsGEI+H0QHMd4CKGyCUAMUsGJiBJDNQNUiYlQEZOKDQclB9cnD9CmCSBYqJBRxQOvBpSQobGfqIAWn8FuYnPI4fsAGyPQz/87MeZtArziguKSpJTGLQK0mtKGGgGHADMSgoYH6AhTMPNHyE0NQzYuEzYzEXFr6CBPQDANAsXKTwAQAA' | base64 -d | gzip -d > /tmp/clickhouse_test_sse42 && chmod a+x /tmp/clickhouse_test_sse42 && /tmp/clickhouse_test_sse42); then
                echo 'Warning! SSE 4.2 instruction set is not supported'
                #exit 3
            fi
        fi
    fi
fi


SUPPORTED_COMMANDS="{start|stop|status|restart|forcestop|forcerestart|reload|condstart|condstop|condrestart|condreload}"
is_supported_command()
{
    echo "$SUPPORTED_COMMANDS" | grep -E "(\{|\|)$1(\||})" &> /dev/null
}


is_running()
{
    [ -r "$CLICKHOUSE_PIDFILE" ] && pgrep -s $(cat "$CLICKHOUSE_PIDFILE") 1> /dev/null 2> /dev/null
}


wait_for_done()
{
    while is_running; do
        sleep 1
    done
}


die()
{
    echo $1 >&2
    exit 1
}


# Check that configuration file is Ok.
check_config()
{
    if [ -x "$BINDIR/$GENERIC_PROGRAM" ]; then
        su -s $SHELL ${CLICKHOUSE_USER} -c "$BINDIR/$GENERIC_PROGRAM extract-from-config --config-file=\"$CLICKHOUSE_CONFIG\" --key=path" >/dev/null || die "Configuration file ${CLICKHOUSE_CONFIG} doesn't parse successfully. Won't restart server. You may use forcerestart if you are sure.";
    fi
}

start()
{
    echo "starting..."
    echo "bin_dir=$BINDIR/$PROGRAM"
    echo "ck user=$CLICKHOUSE_USER:$CLICKHOUSE_GROUP"
    [ -x $BINDIR/$PROGRAM ] || exit 0
    local EXIT_STATUS
    EXIT_STATUS=0

    echo -n "Start $PROGRAM service: "
    ulimit -n 262144

    if is_running; then
        echo -n "already running "
        EXIT_STATUS=1
    else
        mkdir -p $CLICKHOUSE_PIDDIR
        chown -R $CLICKHOUSE_USER:$CLICKHOUSE_GROUP $CLICKHOUSE_PIDDIR
        mkdir -p $CLICKHOUSE_LOGDIR
        if ! is_running; then
            # Lock should not be held while running child process, so we release the lock. Note: obviously, there is race condition.
            # But clickhouse-server has protection from simultaneous runs with same data directory.
            su -s $SHELL ${CLICKHOUSE_USER} -c "flock -u 9; exec -a \"$BINDIR/$PROGRAM\" \"$BINDIR/$PROGRAM\" --daemon --pid-file=\"$CLICKHOUSE_PIDFILE\" --config-file=\"$CLICKHOUSE_CONFIG\""
            echo -n "su -s $SHELL ${CLICKHOUSE_USER} -c \"flock -u 9; exec -a $BINDIR/$PROGRAM $BINDIR/$PROGRAM --daemon --pid-file=$CLICKHOUSE_PIDFILE --config-file=$CLICKHOUSE_CONFIG\""
            EXIT_STATUS=$?
            if [ $EXIT_STATUS -ne 0 ]; then
                break
            fi
        fi
    fi

    if [ $EXIT_STATUS -eq 0 ]; then
        echo "DONE"
    else
        echo "FAILED"
    fi

    return $EXIT_STATUS
}


stop()
{
    local EXIT_STATUS
    EXIT_STATUS=0

    if [ -f $CLICKHOUSE_PIDFILE ]; then

        echo -n "Stop $PROGRAM service: "

        kill -TERM $(cat "$CLICKHOUSE_PIDFILE")

        wait_for_done

        echo "DONE"
    fi
    return $EXIT_STATUS
}


restart()
{
    check_config
    stop
    start
}


forcestop()
{
    local EXIT_STATUS
    EXIT_STATUS=0

    echo -n "Stop forcefully $PROGRAM service: "

    kill -KILL $(cat "$CLICKHOUSE_PIDFILE")

    wait_for_done

    echo "DONE"
    return $EXIT_STATUS
}


forcerestart()
{
    forcestop
    start
}


enable_cron()
{
    return 0
    # [ ! -z "$CLICKHOUSE_CRONFILE" ] && sed -i 's/^#*//' "$CLICKHOUSE_CRONFILE"
}


disable_cron()
{
    return 0

    # [ ! -z "$CLICKHOUSE_CRONFILE" ] && sed -i 's/^#*/#/' "$CLICKHOUSE_CRONFILE"
}


is_cron_disabled()
{
    return 0
    # [ -z "$CLICKHOUSE_CRONFILE" ] && return 0

    # Assumes that either no lines are commented or all lines are commented.
    # Also please note, that currently cron file for ClickHouse has only one line (but some time ago there was more).
    # grep -q -E '^#' "$CLICKHOUSE_CRONFILE";
}


main()
{
    # See how we were called.
    EXIT_STATUS=0
    case "$1" in
    start)
        start && enable_cron
        ;;
    stop)
        disable_cron && stop
        ;;
    restart)
        restart && enable_cron
        ;;
    forcestop)
        disable_cron && forcestop
        ;;
    forcerestart)
        forcerestart && enable_cron
        ;;
    reload)
        restart
        ;;
    condstart)
        is_running || start
        ;;
    condstop)
        is_running && stop
        ;;
    condrestart)
        is_running && restart
        ;;
    condreload)
        is_running && restart
        ;;
    *)
        echo "Usage: $0 $SUPPORTED_COMMANDS"
        exit 2
        ;;
    esac

    exit $EXIT_STATUS
}


# Running commands without need of locking
case "$1" in
status)
    if is_running; then
        echo "$PROGRAM service is running"
        exit 1
    else
        echo "$PROGRAM: process unexpectedly terminated"
        exit 0
    fi
    ;;
esac


(
    if flock -n 9; then
        main "$@"
    else
        echo "Init script is already running" && exit 1
    fi
) 9> $LOCKFILE
