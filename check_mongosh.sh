#!/usr/bin/env bash


### SERVER CHECKS ###
chk_srv_connection() {
    dbEval='db.runCommand({connectionStatus:1}).ok' # 1 means we have connection [Return 0 or 2]
}
chk_srv_memoryUsage() {
    dbEval='db.serverStatus().mem.resident' # amount of used memory in Mebi bites MiB [Return 0] ## TODO treshold option
}
chk_srv_cpuUsage() {
    ret=$( pgrep mongod | xargs -I {} ps -o %cpu -p {} | tail -1 | cut -d ' ' -f 2 ) # [Return 0] ## TODO treshold option
    echo $ret
    exit 0
}
chk_srv_uptimeHours(){
    dbEval='(db.serverStatus().uptime/3600).toFixed(0)'
     # [Return 0] 
}
chk_srv_conns(){
    dbEval='db.serverStatus().connections.current'
     # [Return 0] ## TODO treshold option
}
chk_srv_version(){
    dbEval='db.serverStatus().version' 
    # [Return 0] 
}
### DATABASE CHECKS ###
chk_db_storageSize() {
    dbEval='db.stats().storageSize'  # amount in Mebi bites MiB # [Return 0] ## TODO treshold option
}
chk_db_dataSize() {
    dbEval='db.stats().dataSize' # amount in Mebi bites MiB # [Return 0] ## TODO treshold option
}
chk_db_indexSize() {
    dbEval='db.stats().indexSize' # amount in Mebi bites MiB # [Return 0] ## TODO treshold option
}
chk_db_indexCount() {
    dbEval='db.stats().indexes' # amount in Mebi bites MiB # [Return 0] ## TODO treshold option
}
chk_db_stats(){
    # TODO fmtunit and num by args
    fmtUnitNum=2
    fmtUnitSlug="MiB"
    dbEval='{ let data = db.stats(); 
    let dbFullSize = () => {return db.stats().storageSize+db.stats().indexSize}; 
    let pretySize = (fsize,u) => {return (fsize/1024 ** u).toFixed(2)}
    "Database: " + data.db 
    + " contains: " 
    + data.collections + " Collections, "
    + data.views + " Views, " 
    + data.objects + " Objects, " 
    + data.indexes + " Indexes. " 
    + " Size: " + pretySize(dbFullSize(),'"${fmtUnitNum}"') + " '"${fmtUnitSlug}"'"
    }'
    # [Return 0]
}
chk_db_totalSize(){
    dbEval='db.stats().storageSize+db.stats().indexSize' 
    # [Return 0] ## TODO treshold option
}
### REPLICA SET CHECKS ###
chk_rs_name() {
    dbEval='rs.status().set' # returns string # [Return 0 or 2] 
}
chk_rs_isMaster() {
    dbEval='rs.isMaster().ismaster' # returns t/f [0 of 2]
}
chk_rs_whoIsMaster() {
    dbEval='{
            let o = rs.status().syncSourceHost
            o ? db.hostInfo().system.hostname : o
    }' 
    # if rs.status().syncSourceHost empty that mean this is master [0 or 2]
}
chk_rs_state(){
    # https://www.mongodb.com/docs/manual/reference/replica-states/#replica-set-member-states
    # https://icinga.com/docs/icinga-2/latest/doc/03-monitoring-basics/#check-result-state-mapping
    # Mongo RS      -- | --     Icinga2
    # STARTUP       0  -  3     DOWN_UNKNOWN
    # PRIMARY       1  -  0     UP_OK
    # SECONDARY     2  -  0     UP_OK
    # RECOVERING    3  -  1     UP_WARNING
    # STARTUP2      5  -  3     DOWN_UNKNOWN 
    # UNKNOWN       6  -  2     DOWN_CRITICAL 
    # ARBITER       7  -  0     UP_OK
    # DOWN          8  -  2     DOWN_CRITICAL
    # ROLLBACK      9  -  1     UP_WARNING
    # REMOVED       10 -  2     DOWN_CRITICAL
    dbEval='rs.status().myState'
    ret=$(runCommand)
    case $ret in 
        0) echo "STARTUP";      exit 3;;
        1) echo "PRIMARY";      exit 0;;
        2) echo "SECONDARY";    exit 0;;
        3) echo "RECOVERING";   exit 1;;
        5) echo "STARTUP2";     exit 3;;
        6) echo "UNKNOWN";      exit 2;;
        7) echo "ARBITER";      exit 0;;
        8) echo "DOWN";         exit 2;;
        9) echo "ROLLBACK";     exit 1;;
        10) echo "REMOVED";     exit 2;;
        *) echo "UNDEFINED";    exit 3;; 

    esac
}



# chk_custom(){}
# nd_eval(){} #not definied eval use only for testing!!!! Add specific function to script

# Utility commands not adjusted to icinga
util_srv_connsByIp(){
    # [Return 0] 
    dbEval='{ db.currentOp(true).inprog.reduce(
    (accumulator, connection) => {
        ipaddress = connection.client ? connection.client.split(":")[0] : "Internal";
        accumulator[ipaddress] = (accumulator[ipaddress] || 0) + 1;
        accumulator["TOTAL_CONNECTION_COUNT"]++;
        return accumulator;
    },
    { TOTAL_CONNECTION_COUNT: 0 }
    ) 
    } '
} 
runCommand(){
     $mongosh_cmd \
        --username "${dbUser}" \
        --password "${dbPass}" \
        --authenticationDatabase "${dbAuth}" \
        --eval "${dbEval}" \
        --quiet \
        "${dbAddr}"
}
printOutput() {
    ret=$(runCommand)
    echo "${ret}"
    if [[ ! ( -z $ret || $ret =~ .*MongoServerError.* ) ]]; then
        exit 0
    fi

    exit 2
    # [[ $ret ]] && echo "${ret}" ; quit(0) || quit (2)
}

main(){

    mongosh_cmd=$(whereis mongosh | cut -d : -f 2 | sed 's/[[:space:]]//g')
    if [[  -z $mongosh_cmd ]]; then
        [[  -f /usr/local/bin/mongosh ]] && mongosh_cmd=/usr/local/bin/mongosh;
        [[  -f /usr/bin/mongosh ]] && mongosh_cmd=/usr/bin/mongosh;
        [[  -z $mongosh_cmd ]] && echo "mongosh not found" && exit 3
    fi

    options=$(getopt -o c:u:p:a: --long connectionString:,username:,password:,authenticationDatabase: -- "$@")

    eval set -- "$options"

    while true; do
        case "${1}" in
            -a | --authenticationDatabase)
                dbAuth="${2}"
                shift 2
                ;;
            -u | --username)
                dbUser="${2}"
                shift 2
                ;;
            -p | --password)
                dbPass="${2}"
                shift 2
                ;;
            -c | --connectionString)
                dbAddr="${2}"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Invalid option: $1" >&2
                exit 3
                ;;
        esac
    done

    # Process the command name  after options
    if [[ $# -gt 0 ]]; then
        case "${1}" in 
            chk_srv_connection) 
                chk_srv_connection
                ;;
            chk_srv_memoryUsage)
                chk_srv_memoryUsage 
                ;; 
            chk_srv_cpuUsage) 
                chk_srv_cpuUsage
                ;; 
            chk_srv_uptimeHours) 
                chk_srv_uptimeHours
                ;;
            chk_srv_conns) 
                chk_srv_conns
                ;;
            chk_srv_version) 
                chk_srv_version
                ;;
            chk_db_storageSize) 
                chk_db_storageSize
                ;; 
            chk_db_dataSize) 
                chk_db_dataSize
                ;;
            chk_db_indexSize) 
                chk_db_indexSize
                ;; 
            chk_db_indexCount) 
                chk_db_indexCount
                ;; 
            chk_db_stats) 
                chk_db_stats
                ;;
            chk_db_totalSize) 
                chk_db_totalSize
                ;;
            chk_rs_name) 
                chk_rs_name
                ;; 
            chk_rs_isMaster) 
                chk_rs_isMaster
                ;; 
            chk_rs_whoIsMaster) 
                chk_rs_isMaster
                ;; 
            chk_rs_state) 
                chk_rs_state
                ;;      
            util_srv_connsByIp)
                util_srv_connsByIp
                ;;
            *)
                echo "Invalid command"
                exit 3
                ;;
        esac
    else
        echo "No command provided"
        exit 3
    fi
    
    printOutput
}



main "$@"

# chk_srv_connection() 
# chk_srv_memoryUsage() 
# chk_srv_cpuUsage() 
# chk_db_storageSize() 
# chk_db_dataSize() 
# chk_db_indexSize() 
# chk_db_indexCount() 
# chk_rs_name() 
# chk_rs_isMaster() 
# chk_rs_state()
# chk_db_stats()
# chk_db_totalSize()
# chk_srv_uptimeHours()
# chk_srv_conns()
# chk_srv_version()

