#!/usr/bin/perl -w

#CESGA-XEN-ZABBIX
#https://github.com/CESGA/CESGA-XEN-ZABBIX
#Developed by Frco. Javier Rial <fjrial@cesga.es>
#www.CESGA.es
#
#This script queries zabbix database to search for hosts in a specific hostgroup (XEN-SERVERS)
#It assumes that every host obtained is a xen-server, so it'll check for nagios_nrpe port (5666) to
#execute check_xen command (using check_nrpe program). Obtains output, parse it, and submit to zabbix.
#
#Usage: install this script as a crontab every X minutes to get stats every X
#Tips: you can add a discovery rule in zabbix to check a network range and tcp port 5666 to auto-add hosts to group in zabbix
#
#TODO: CHANGE SOME MYSQL QUERIES TO ZABBIX API CALLS
#TODO: USE THREADS TO INCREASE PERFORMANCE
#TODO: NEED TO CHANGE SOME VARS TO GLOBAL VARS TO CHANGE SOME COMMANDS EASILY 
#TODO: Learn perl to avoid common mistakes that are (that's for sure) present in this code. Sorry :(
#
#Requirementes:
# Command check_nrpe in zabbix_server
# You can build it from sources here: http://exchange.nagios.org/directory/Addons/Monitoring-Agents/NRPE--2D-Nagios-Remote-Plugin-Executor/details
#
# JSON::XS;
# LWP::UserAgent;
# DBI
#
# xenserver.pm (included)
# Zabbix.pm (included, this is a modified version) that has two new methos (post,update)
# Original version can be found here: https://github.com/sjohnston/Net-Zabbix/blob/master/lib/Net/Zabbix.pm
#
#This program is free software; you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation; either version 2 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#



use DBI;
use Data::Dumper;
use xenserver;

#TODO replace these mysql calls with api calls
$dbh = DBI->connect('dbi:mysql:zabbix','user_mysql_zabbix','pass_mysql_zabbix') or die "Connection Error: $DBI::errstr\n";
$sql = "select groupid from groups where name='XEN-SERVERS'";
$sth = $dbh->prepare($sql);
$sth->execute or die "SQL Error: $DBI::errstr\n";

while (@row = $sth->fetchrow_array) {
	#obter hosts
	$sql1 = "select hostid from hosts_groups where groupid=@row";
	$sth1 = $dbh->prepare($sql1);
 	$sth1->execute or die "SQL Error: $DBI::errstr\n";
	
	while (@row1 = $sth1->fetchrow_array) {
		#xa temos xen-servers
		$sql2 = "select dns,ip,host,useip from hosts where hostid=@row1";
		$sth2 = $dbh->prepare($sql2);
	        $sth2->execute or die "SQL Error: $DBI::errstr\n";
		
		while (@row2 = $sth2->fetchrow_array) {
			&update_host(@row2);
		}

	}
} 



#subroutine to update a zabbix specific host
#it will:
#-execute check_xen (nrpe nagios plugin)
#-parse info obtained
#-create/update items in zabbix 
sub update_host (){

	#useip determine if we have to check our zabbix host by ip or by dns
	if ($row2[3] eq 0) # by dns
		{
		$connect_to=$row2[0];
		}
	else #default by ip
		{
		$connect_to=$row2[1];
		}
	
	#TODO usar threads 
	#get info from nagios plugin
	#-t 1 (timeout 1 second)
	#adjust the path to where you have put the check_nrpe command
	$output=`/root/crons/check_nrpe -H $connect_to -c check_xen -t 1`;
	&parse_output_nrpe($output);

}

#subroutine to parse output from check_nrpe check_xen
#output eample
#XEN OK - VM : Domain-0: hosting1: hosting2: hosting3|{totalMEM=8023} Domain-0=1065205;383 hosting1=19464540;768 hosting2=9875774;768 hosting3=11454148;512
#XEN $status - VM : $DOMAIN0: $DOMAIN1: $DOMAINn | {$TOTALMEM} $DOMAIN0=$CPU;$MEM $DOMAIN1=$CPU;$MEM $DOMAINn=$CPU;$MEM

sub parse_output_nrpe(){
	#STATUS 2 = UNKNOWN (by default)
	#STATUS 1 = OK
	#STATUS 0 = PROBLEM
	$status_xen = 2;
	$mem_xen = 0;
	$vm_info = "";

	#get status
	$status = substr $output, 4, 2;
	if ($status eq "OK"){
		$status_xen=1;
		}
	else	{
		$status_xen=0;
		return 1;
		}

	#get mem
	#search for "{totalMEM=" in output
	$pos=index($output, "{totalMEM="); 
	$pos2=index($output, "}");
	$length=$pos2-$pos-length("{totalMEM=");
	$mem_xen = substr $output,$pos+length("{totalMEM="),$length;

	#create table with vms info
	$vm_info=substr $output,$pos2+2;

	#@row1 is the hostid of this xen server at zabbix
	$info_xen = new xenserver($row2[2],$row1[0],$status_xen, $mem_xen,$vm_info);
	
	#proceed with this xen-server
	$info_xen->submit_zabbix();
}

