#!/bin/bash
### BEGIN INIT INFO
# Provides:          thingsboard
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ThingsBoard IoT Platform
### END INIT INFO

JAVA_OPTS="-Dplatform=deb -Dinstall.data_dir=/usr/share/thingsboard/data"
THINGSBOARD_JAR="/usr/share/thingsboard/bin/thingsboard.jar"
THINGSBOARD_LOG="/var/log/thingsboard/thingsboard.log"
THINGSBOARD_PID="/var/run/thingsboard.pid"

start() {
    echo "Starting ThingsBoard..."
    if [ -f $THINGSBOARD_PID ] && kill -0 $(cat $THINGSBOARD_PID) 2>/dev/null; then
        echo "ThingsBoard is already running"
        return 1
    fi
    java $JAVA_OPTS -jar $THINGSBOARD_JAR > $THINGSBOARD_LOG 2>&1 &
    echo $! > $THINGSBOARD_PID
    echo "ThingsBoard started"
}

stop() {
    echo "Stopping ThingsBoard..."
    if [ -f $THINGSBOARD_PID ]; then
        kill $(cat $THINGSBOARD_PID) 2>/dev/null
        rm -f $THINGSBOARD_PID
        echo "ThingsBoard stopped"
    else
        echo "ThingsBoard is not running"
    fi
}

restart() {
    stop
    sleep 3
    start
}

status() {
    if [ -f $THINGSBOARD_PID ] && kill -0 $(cat $THINGSBOARD_PID) 2>/dev/null; then
        echo "ThingsBoard is running (PID: $(cat $THINGSBOARD_PID))"
    else
        echo "ThingsBoard is not running"
        return 1
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0