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
#TODO: USE THREADS TO INCREASE PERFORMANCE
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
# Zabbix.pm (included, this is a modified version) that has new methods (post,update)
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
use Zabbix;

#GLOBAL VARS
$MYSQL_ZABBIX_DB = 'zabbix';
$MYSQL_ZABBIX_USER = 'user';
$MYSQL_ZABBIX_PASS = 'pass';
$ZABBIX_HOSTGROUPNAME_XEN_SERVERS = 'XEN-SERVERS';
$ZABBIX_URL = 'http://url.zabbix.es';
$ZABBIX_SERVER_IP = '8.8.8.8';
$ZABBIX_USER_API = 'Admin';
$ZABBIX_USER_PASS = 'Admin_api';
$PATH_ZABBIX_SENDER_BIN = '/usr/local/bin/zabbix_sender';
$PATH_CHECK_NRPE_BIN = '/root/crons/check_nrpe';
$TIMEOUT_CHECK_NRPE = 1;

#get hostgroupid in zabbix that belons to $ZABBIX_HOSTGROUPNAME_XEN_SERVERS
my $zabbixsession = Net::Zabbix->new($main::ZABBIX_URL,$main::ZABBIX_USER_API,$main::ZABBIX_USER_PASS);
my $hostgroupid = $zabbixsession->get('hostgroup', { output => 'extend', filter => { name => $ZABBIX_HOSTGROUPNAME_XEN_SERVERS }});
my @my_array_1=$hostgroupid->{'result'};
my $groupid_zabbix=$my_array_1[0][0]->{'groupid'};

#now, fetch hostids from groupid
my $hostids = $zabbixsession->get('host', { output => 'extend', groupids => $groupid_zabbix });
my @my_array_2=$hostids->{'result'};
for $aref ( @my_array_2 ) {
	#for each host
	for $bref (@$aref) {
	    #now, we need extra info from each host (to check it by ip/dnsname)
	    $host_info = $zabbixsession->get('host', { output => 'extend', hostids => $bref->{'hostid'}});
	    &update_host($host_info);
	    }
    }

#subroutine to update a zabbix specific host
#it will:
#-execute check_xen (nrpe nagios plugin)
#-parse info obtained
#-create/update items in zabbix 
sub update_host (){

	#useip determine if we have to check our zabbix host by ip or by dns
	if ($host_info->{result}[0]->{'useip'} eq 0) # by dns
		{
		$connect_to=$host_info->{result}[0]->{'dns'};
		}
	else #default by ip
		{
		$connect_to=$host_info->{result}[0]->{'ip'};
		}
	
	#TODO usar threads 
	#get info from nagios plugin
	#-t 1 (timeout 1 second)
	#adjust the path to where you have put the check_nrpe command
	$output=`$PATH_CHECK_NRPE_BIN -H $connect_to -c check_xen -t $TIMEOUT_CHECK_NRPE`;
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
		return 0;
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
	$info_xen = new xenserver($host_info->{result}[0]->{'host'},$bref->{'hostid'},$status_xen, $mem_xen,$vm_info);
	
	#proceed with this xen-server
	$info_xen->submit_zabbix();
}

