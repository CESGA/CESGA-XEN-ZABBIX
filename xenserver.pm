#CESGA-XEN-ZABBIX
#https://github.com/CESGA/CESGA-XEN-ZABBIX
#Developed by Frco. Javier Rial <fjrial@cesga.es>
#www.CESGA.es
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

#data structure for storing values of a xenserver instance
use Zabbix;
package xenserver;

sub new
{
    my $class = shift;
    my $self = {
	#name of host in zabbix
	_xen_host => shift,
	#host id on zabbix
	_xen_hostid => shift,
	#xen service status
        _xen_status => shift,
	#all mem avaliable on this xen-server
        _xen_mem => shift,
	#string with domus info, should be better implemented, but now, it works
        _xen_vms_info => shift,
    };
    bless $self, $class;
    return $self;
}

sub submit_zabbix {
    my( $self ) = @_;

    #if status down, don't continue because connection wasn't succesfull
    if ($self->{_xen_status} == 2 )
		{
		return 0;
		}

    #each domu info has a blank space before, split
    my @domains = split(' ', $self->{_xen_vms_info});

    #var to summarize the mem used by every domu of this xen-server
    my $total_used = 0;

    #process every domu of this xen-server
    foreach my $val (@domains) {
	$pos=index($val,"=");
    	$domain = substr $val, 0, $pos;
	$pos1=index($val,";");
	$cpu = substr $val, $pos+1, $pos1-$pos-1;
	$mem = substr $val, $pos1+1;

	$total_used=$total_used+$mem;

	#we need this because there is a Domain-0 in every xen-server.. and we need that all items are unique
	if ($domain eq 'Domain-0'){
		$dom0 = $self->{_xen_host}."_";
		}
	else{
		$dom0 = '';
		}
	

	#send DOMUs info through perl zabbix api
	#1.- check if exist in this xen server
	my $zabbixsession = Net::Zabbix->new($main::ZABBIX_URL,$main::ZABBIX_USER_API,$main::ZABBIX_USER_PASS);
	#this should return 3 items: domu_$dom0.$domain,domu_$dom0.$domain_mem and domu_$dom0.$domain_cpu
	my $itemids = $zabbixsession->get('item', { output => 'extend', patternKey => "domu_".$dom0.$domain });
	my @my_array=$itemids->{'result'};

	#if this return 0 items.. we must create items for this domus
	if(not defined $my_array[0][0]->{'itemid'}){
		#domu name
                my $zabbixsession = Net::Zabbix->new($main::ZABBIX_URL,$main::ZABBIX_USER_API,$main::ZABBIX_USER_PASS);
                my $itemid_created = $zabbixsession->post('item', { description => 'domu_'.$dom0.$domain, key_ => 'domu_'.$dom0.$domain, hostid => $self->{_xen_hostid}, data_type => 0, type => 2,value_type => 4,trapper_hosts => ''});
		#domu memory
                my $itemid_created1 = $zabbixsession->post('item', { description => 'domu_'.$dom0.$domain.'_mem', key_ => 'domu_'.$dom0.$domain.'_mem', hostid => $self->{_xen_hostid}, units => 'B',formula => 1048576,data_type => 0, type => 2,value_type => 3,trapper_hosts => '',multiplier => '1'});
		#domu cpu
		my $itemid_created2 = $zabbixsession->post('item', { description => 'domu_'.$dom0.$domain.'_cpu', key_ => 'domu_'.$dom0.$domain.'_cpu', hostid => $self->{_xen_hostid}, data_type => 0, type => 2,value_type => 0,delta => 1, units => '%', trapper_hosts => ''});

		}
	#otherwise we must check if items belongs to this host, it they belong, we submit the data, otherwise we reassign the item to this xen-server (maybe it was running in other xen server previous 
	else {
		#process first row to check the hostid
		if ($my_array[0][0]->{'hostid'} == $self->{_xen_hostid}){
		#if they match, we are using the correct host, so, just send info to items
                        #update domu_name
	                $command="$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host ".$self->{_xen_host}." --key domu_".$dom0.$domain." --value \"".$domain."\" -vv";
       		        # update domu_name_mem
	                $command1="$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host ".$self->{_xen_host}." --key domu_".$dom0.$domain."_mem --value \"".$mem."\" -vv";
			# update domu_name_cpu
			$command2="$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host ".$self->{_xen_host}." --key domu_".$dom0.$domain."_cpu --value \"".$cpu."\" -vv";

			#execute commands
			$out=`$command`;
			$out=`$command1`;	
			$out=`$command2`;
			}
		#if host doesnt match current host, update items
		else{
			#reassign domus items to this xen server 
			my $itemid_updated = $zabbixsession->update('item', { itemid => $my_array[0][0]->{'itemid'},hostid => $self->{_xen_hostid} });
                        my $itemid_updated1 = $zabbixsession->update('item', { itemid => $my_array[0][1]->{'itemid'},hostid => $self->{_xen_hostid} });
                        my $itemid_updated2 = $zabbixsession->update('item', { itemid => $my_array[0][2]->{'itemid'},hostid => $self->{_xen_hostid} });

			#send info 
                        # send domu_name
                        $command="$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host ".$self->{_xen_host}." --key domu_".$dom0.$domain." --value \"".$domain."\"";
                        # send domu_name_mem
                        $command1="$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host ".$self->{_xen_host}." --key domu_".$dom0.$domain."_mem --value \"".$mem."\"";
                        # send domu_name_cpu
                        $command2="$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host ".$self->{_xen_host}." --key domu_".$dom0.$domain."_cpu --value \"".$cpu."\"";

                        #execute commands
                        $out=`$command`;
                        $out=`$command1`;
                        $out=`$command2`;
			
			}
             }

	
    }

    
    #execute only if xen_status = OK 
    $out=`$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host $self->{_xen_host} --key xen_status --value "$self->{_xen_status}"`;
    $out=`$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host $self->{_xen_host} --key xen_mem --value "$self->{_xen_mem}"`;

    #mem_free = total - used by domus
    $free=$self->{_xen_mem}-$total_used;
    $out=`$main::PATH_ZABBIX_SENDER_BIN --zabbix-server $main::ZABBIX_SERVER_IP --host $self->{_xen_host} --key xen_mem_free --value "$free"`;

	

    return 1;
}
sub DESTROY
{
    print "   xenserver::DESTROY called\n";
}
1;
