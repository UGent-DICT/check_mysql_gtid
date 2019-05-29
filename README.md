# check_mysql_gtid
Icinga compatible check for errant GTIDs in a mysql cluster

## Description

This script checks for every replica in a MySQL cluster, if all GTIDs exist on the primary node.
If a replica has GTIDs that only exist on the replica, then these transactions are not replicated
across the MySQL cluster.

## Dependencies

- mysql client
- orchestrator 2.0 (or higher)

## Usage

Usage : check_mysql_gtid [cluster-name]

The script takes clustername as an optional parameter. If set only the nodes of that cluster will
be checked. If not set, all clusters managed by orchestrator will be checked.

Output:

MYSQL_CLUSTER_GTID WARNING : replicas containing unreplicated GTIDs : cluster2

Cluster cluster1 (primary : node11) :
 - node12 : OK
 - node13 : OK

Cluster cluster2 (primary : node21) :
 - node22 : GTIDs only exist on the replica :
  38da654e-04bf-11e7-b4e9-aa000090031f:1-461

A MySQL credentials file is used to provide login credentials to the mysql command.
It is unsafe to provide the password as a parameter on the command line.
The filename is passed to the mysql command as a parameter and should be readable
only by the user that executes this script.

Copy `check_mysql_gtid_credentials.sample` to the same folder as the script and rename
it to `check_mysql_gtid_credentials`.

Format of the credentials file :

[client]
user=
password=

## License

MIT License

(see LICENSE file)
